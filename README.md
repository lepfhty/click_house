![](./doc/logo.svg?sanitize=true)

# ClickHouse Ruby driver

[![CI](https://github.com/tenjin/click_house/actions/workflows/main.yml/badge.svg)](https://github.com/tenjin/click_house/actions/workflows/main.yml)

Each release is a git tag and a gem on GitHub Packages; nothing is published to
RubyGems. See [Releases](https://github.com/tenjin/click_house/releases) for the latest
version. Install from the tag:

```ruby
# Gemfile
gem 'click_house', git: 'https://github.com/tenjin/click_house.git', tag: 'vX.Y.Z'
```

Or from GitHub Packages, which needs a GitHub token with `read:packages` (for example
`BUNDLE_RUBYGEMS__PKG__GITHUB__COM=<user>:<token>`) even though the package is public.
Keep the `source` block: RubyGems has an unrelated `click_house` gem, and the block stops
Bundler from installing that one instead.

```ruby
# Gemfile
source 'https://rubygems.pkg.github.com/tenjin' do
  gem 'click_house', '~> X.Y'
end
```

A modern Ruby database driver for ClickHouse. [ClickHouse](https://clickhouse.yandex)
is a high-performance column-oriented database management system developed by
[Yandex](https://yandex.com/company) which operates Russia's most popular search engine.

> This development was inspired by currently [unmaintainable alternative](https://github.com/archan937/clickhouse)
> but rewritten and well tested

### Why use the HTTP interface and not the TCP interface?

Well, the developers of ClickHouse themselves [discourage](https://github.com/yandex/ClickHouse/issues/45#issuecomment-231194134) using the TCP interface.

> TCP transport is more specific, we don't want to expose details.
Despite we have full compatibility of protocol of different versions of client and server, we want to keep the ability to "break" it for very old clients. And that protocol is not too clean to make a specification.

Yandex uses HTTP interface for working from Java and Perl, Python and Go as well as shell scripts.

# TOC

* [Configuration](#configuration)
* [Usage](#usage)
* [Queries](#queries)
* [Insert](#insert)
* [Create a table](#create-a-table)
* [Alter table](#alter-table)
* [Type casting](#type-casting)
* [Using with a connection pool](#using-with-a-connection-pool)
* [Using with Rails](#using-with-rails)
* [Using with ActiveRecord](#using-with-activerecord)
* [Using with RSpec](#using-with-rspec)
* [Development](#development)

## Configuration

### Recommended

The defaults stay compatible with old servers and every setup. For Ruby 3.3, Faraday
1.10.6+ or 2, and ClickHouse 26.x, turn these on. On Faraday 2, persistent connections
need `gem 'faraday-net_http_persistent'` in your Gemfile, and
`require 'faraday/net_http_persistent'` outside Bundler.

```ruby
ClickHouse.config do |config|
  # ... Connection info here

  # Verify the server's certificate over https
  config.ssl_verify = true

  # Reuse sockets instead of a new TCP (and TLS) handshake per query
  # Run the first query after Puma or Unicorn forks, so each worker opens its own sockets.
  config.adapter = :net_http_persistent

  # Settings sent with every query, selects included
  config.global_params = { max_execution_time: 300 } # the server stops runaway queries
  config.timeout = 330                               # safety net above max_execution_time
  config.open_timeout = 5

  # Parse JSON numbers as Float; Decimals are requested as strings to keep precision
  config.parse_floats = true
end
```

By default the JSON parser turns every fractional number into a `BigDecimal`, so Decimal
columns keep their precision, and Float32/Float64 columns are then converted back to
`Float`, which slows parsing float-heavy results by about 60%. `parse_floats` parses
them as `Float` and has the server send Decimal values as strings instead.

`max_execution_time` also applies to `execute` and `insert`. Lift it for long jobs such as
backfills: `execute(sql, params: { max_execution_time: 0 })`.

[doc/recommended-config.md](doc/recommended-config.md) explains each setting and covers
ClickHouse before 26.1, `readonly=1` users and proxies that reject large headers.

### All options

```ruby
ClickHouse.config do |config|
  config.logger = Logger.new(STDOUT)
  config.adapter = :net_http
  # or an adapter followed by its arguments, e.g. [:net_http_persistent, { pool_size: 5 }]
  config.database = 'metrics'
  config.url = 'http://localhost:8123'
  config.timeout = 60
  config.open_timeout = 3
  config.ssl_verify = false
  config.headers = {}

  # or provide connection options separately
  config.scheme = 'http'
  config.host = 'localhost'
  config.port = 8123

  # if you use HTTP basic Auth
  config.username = 'user'
  config.password = 'password'

  # if you want to add settings to all queries
  config.global_params = { mutations_sync: 1 }
  
  # choose a ruby JSON parser (default one)
  config.json_parser = ClickHouse::Middleware::ParseJson
  # or Oj parser
  config.json_parser = ClickHouse::Middleware::ParseJsonOj

  # Parser options: merge into the existing hashes, since they hold defaults. Settings
  # loaded with assign (e.g. from YAML) replace them, so merge those in Ruby instead
  # passed to JSON.parse; default { decimal_class: BigDecimal }
  config.json_load_options = config.json_load_options.merge(decimal_class: BigDecimal)
  # passed to Oj.load; defaults in lib/click_house/config.rb
  config.oj_load_options = config.oj_load_options.merge(bigdecimal_load: :bigdecimal)

  # JSON.dump (default one)
  config.json_serializer = ClickHouse::Serializer::JsonSerializer
  # or Oj.dump
  config.json_serializer = ClickHouse::Serializer::JsonOjSerializer

  # true parses JSON numbers as Float and asks the server to quote Decimal values
  config.parse_floats = false

  # true returns rows with symbol keys instead of strings
  config.symbolize_keys = false
end
```

Alternative, you can assign configuration parameters via a hash

```ruby
ClickHouse.config.assign(logger: Logger.new(STDOUT))
```

Now you are able to communicate with ClickHouse:

```ruby
ClickHouse.connection.ping #=> true
```
You can easily build a new raw connection and override any configuration parameter
(such as database name, connection address)

```ruby
@connection = ClickHouse::Connection.new(ClickHouse::Config.new(logger: Rails.logger))
@connection.ping
```

## Usage

```ruby
ClickHouse.connection.ping #=> true
ClickHouse.connection.replicas_status #=> true

ClickHouse.connection.databases #=> ["default", "system"]
ClickHouse.connection.create_database('metrics', if_not_exists: true, engine: nil, cluster: nil)
ClickHouse.connection.drop_database('metrics', if_exists: true, cluster: nil)

ClickHouse.connection.tables #=> ["visits"]
ClickHouse.connection.describe_table('visits') #=> [{"name"=>"id", "type"=>"FixedString(16)", "default_type"=>""}]
ClickHouse.connection.table_exists?('visits', temporary: nil) #=> true
ClickHouse.connection.drop_table('visits', if_exists: true, temporary: nil, cluster: nil)
ClickHouse.connection.create_table(*) # see <Create a table> section
ClickHouse.connection.truncate_table('name', if_exists: true, cluster: nil)
ClickHouse.connection.truncate_tables(['table_1', 'table_2'], if_exists: true, cluster: nil)
ClickHouse.connection.truncate_tables # will truncate all tables in database
ClickHouse.connection.rename_table('old_name', 'new_name', cluster: nil)
ClickHouse.connection.rename_table(%w[table_1 table_2], %w[new_1 new_2], cluster: nil)
ClickHouse.connection.alter_table('table', 'DROP COLUMN user_id', cluster: nil)
ClickHouse.connection.add_index('table', 'ix', 'has(b, a)', type: 'minmax', granularity: 2, cluster: nil)
ClickHouse.connection.drop_index('table', 'ix', cluster: nil)

ClickHouse.connection.select_all('SELECT * FROM visits')
ClickHouse.connection.select_one('SELECT * FROM visits LIMIT 1')
ClickHouse.connection.select_value('SELECT ip FROM visits LIMIT 1')
ClickHouse.connection.explain('SELECT * FROM visits CROSS JOIN visits')
```

## Queries
### Select All

Select all type-casted result set

```ruby
@result = ClickHouse.connection.select_all('SELECT * FROM visits')

# all enumerable methods are delegated like #each, #map, #select etc
# results of #to_a is TYPE CASTED
@result.to_a #=> [{"date"=>#<Date: 2000-01-01>, "id"=>1}]

# raw results (WITHOUT type casting)
# much faster if selecting a large amount of data
@result.data #=> [{"date"=>"2000-01-01", "id"=>1}, {"date"=>"2000-01-02", "id"=>2}]

# you can access raw data
@result.meta #=> [{"name"=>"date", "type"=>"Date"}, {"name"=>"id", "type"=>"UInt32"}]
@result.statistics #=> {"elapsed"=>0.0002271, "rows_read"=>2, "bytes_read"=>12}
@result.summary #=> ClickHouse::Response::Summary
@result.headers #=> {"x-clickhouse-query-id"=>"9bf5f604-31fc-4eff-a4b5-277f2c71d199"}
@result.types #=> [Hash<String|Symbol, ClickHouse::Ast::Statement>]
```

### Select Value

Select value returns exactly one type-casted value

```ruby
ClickHouse.connection.select_value('SELECT COUNT(*) from visits') #=> 0
ClickHouse.connection.select_value("SELECT toDate('2019-01-01')") #=> #<Date: 2019-01-01>
ClickHouse.connection.select_value("SELECT toDateOrZero(NULL)") #=> nil
```

### Select One

Returns a record hash with the column names as keys and column values as values.

```ruby
ClickHouse.connection.select_one('SELECT date, SUM(id) AS sum FROM visits GROUP BY date')
#=> {"date"=>#<Date: 2000-01-01>, "sum"=>1}
```

### Execute Raw SQL

By default, gem provides parser for `JSON` and `CSV` response formats. Type conversion
available for the `JSON`.

```ruby
# format not specified
response = ClickHouse.connection.execute <<~SQL
  SELECT count(*) AS counter FROM rspec
SQL

response.body #=> "2\n"

# JSON
response = ClickHouse.connection.execute <<~SQL
  SELECT count(*) AS counter FROM rspec FORMAT JSON
SQL

response.body #=> {"meta"=>[{"name"=>"counter", "type"=>"UInt64"}], "data"=>[{"counter"=>"2"}], "rows"=>1, "statistics"=>{"elapsed"=>0.0002412, "rows_read"=>2, "bytes_read"=>4}}

# CSV
response = ClickHouse.connection.execute <<~SQL
  SELECT count(*) AS counter FROM rspec FORMAT CSV
SQL

response.body #=> [["2"]]

# You may use any format supported by ClickHouse
response = ClickHouse.connection.execute <<~SQL
  SELECT count(*) AS counter FROM rspec FORMAT RowBinary
SQL

response.body #=> "\u0002\u0000\u0000\u0000\u0000\u0000\u0000\u0000"
```

## Insert

When column names and values are transferred separately, data sends to the server 
using `JSONCompactEachRow` format by default.

```ruby
ClickHouse.connection.insert('table', columns: %i[id name]) do |buffer|
  buffer << [1, 'Mercury']
  buffer << [2, 'Venus']
end

# or
ClickHouse.connection.insert('table', columns: %i[id name], values: [[1, 'Mercury'], [2, 'Venus']])
```

When rows are passed as an Array or a Hash, data sends to the server
using `JSONEachRow` format by default.

```ruby
ClickHouse.connection.insert('table', [{ name: 'Sun', id: 1 }, { name: 'Moon', id: 2 }])

# or
ClickHouse.connection.insert('table', { name: 'Sun', id: 1 })

# for ruby < 3.0 provide an extra argument
ClickHouse.connection.insert('table', { name: 'Sun', id: 1 }, {})

# or
ClickHouse.connection.insert('table') do |buffer|
  buffer << { name: 'Sun', id: 1 }
  buffer << { name: 'Moon', id: 2 }
end
```

Sometimes it's needed to use other format than `JSONEachRow` For example if you want to send BigDecimal's 
you could use `JSONStringsEachRow` format so string representation of `BigDecimal` will be parsed:

```ruby
ClickHouse.connection.insert('table', { name: 'Sun', id: '1' }, format: 'JSONStringsEachRow')
# or
ClickHouse.connection.insert_rows('table', { name: 'Sun', id: '1' }, format: 'JSONStringsEachRow')
# or
ClickHouse.connection.insert_compact('table', columns: %w[name id], values: %w[Sun 1], format: 'JSONCompactStringsEachRow')
```

See the [type casting](#type-casting) section to insert the data in a proper way.

## Create a table
### Create table using DSL

```ruby
ClickHouse.connection.create_table('visits', if_not_exists: true, engine: 'MergeTree(date, (year, date), 8192)') do |t|
  t.FixedString :id, 16
  t.UInt16      :year, low_cardinality: true
  t.Date        :date
  t.DateTime    :time, 'UTC'
  t.Decimal     :money, 5, 4
  t.String      :event
  t.UInt32      :user_id
  t.IPv4        :ipv4
  t.IPv6        :ipv6
end
```

### Create nullable columns

```ruby
ClickHouse.connection.create_table('visits', engine: 'TinyLog') do |t|
  t.UInt16 :id, 16, nullable: true
end
```

### Set column options

```ruby
ClickHouse.connection.create_table('visits', engine: 'MergeTree(date, (year, date), 8192)') do |t|
  t.UInt16  :year
  t.Date    :date
  t.UInt16  :id, 16, default: 0, ttl: 'date + INTERVAL 1 DAY'
end
```

### Define column with custom SQL

```ruby
ClickHouse.connection.create_table('visits', engine: 'TinyLog') do |t|
  t << "vendor Enum('microsoft' = 1, 'apple' = 2)"
  t << "tags Array(String)"
end
```

### Define nested structures

```ruby
ClickHouse.connection.create_table('visits', engine: 'TinyLog') do |t|
  t.UInt8 :id
  t.Nested :json do |n|
    n.UInt8 :cid
    n.Date  :created_at
    n.Date  :updated_at
  end
end
```

### Set table options

```ruby
ClickHouse.connection.create_table('visits',
  order: 'year',
  ttl: 'date + INTERVAL 1 DAY',
  sample: 'year',
  settings: 'index_granularity=8192',
  primary_key: 'year',
  engine: 'MergeTree') do |t|
  t.UInt16  :year
  t.Date    :date
end
```

### Create table with raw SQL

```ruby
ClickHouse.connection.execute <<~SQL
  CREATE TABLE visits(int Nullable(Int8), date Nullable(Date)) ENGINE TinyLog
SQL
```

## Alter table
### Alter table with DSL
```ruby
ClickHouse.connection.add_column('table', 'column_name', :UInt64, default: nil, if_not_exists: nil, after: nil, cluster: nil)
ClickHouse.connection.drop_column('table', 'column_name', if_exists: nil, cluster: nil)
ClickHouse.connection.clear_column('table', 'column_name', partition: 'partition_name', if_exists: nil, cluster: nil)
ClickHouse.connection.modify_column('table', 'column_name', type: :UInt64, default: nil, if_exists: false, cluster: nil)
```

### Alter table with SQL

```ruby
# By SQL in argument
ClickHouse.connection.alter_table('table', 'DROP COLUMN user_id', cluster: nil)

# By SQL in a block
ClickHouse.connection.alter_table('table', cluster: nil) do
  <<~SQL
    MOVE PART '20190301_14343_16206_438' TO VOLUME 'slow'
  SQL
end
```

## Type casting

By default gem provides all necessary type casting, but you may overwrite or define
your own logic. if you need to redefine all built-in types with your implementation,
just clear the default type system:

```ruby
ClickHouse.types.clear
ClickHouse.types # => {}
ClickHouse.types.default #=> #<ClickHouse::Type::UndefinedType>
```

Fractional numbers are parsed as `BigDecimal` and then cast per column, which is slow for
Float32/Float64 columns. See `parse_floats` under [Recommended](#recommended).

Type casting works automatically when fetching data, when inserting data, you must serialize the types yourself

```sql
CREATE TABLE assets(visible Boolean, tags Array(Nullable(String))) ENGINE Memory
```

```ruby
# cache table schema in a class variable
@schema = ClickHouse.connection.table_schema('assets')

# Json each row
ClickHouse.connection.insert('assets', @schema.serialize({'visible' => true, 'tags' => ['ruby']}))

# Json compact
ClickHouse.connection.insert('assets', columns: %w[visible tags]) do |buffer|
  buffer << [
    @schema.serialize_column("visible", true),
    @schema.serialize_column("tags", ['ruby']),
  ]
end
```

## Using with a connection pool

`ClickHouse::Config.new` starts from the defaults, not from `ClickHouse.config`. Use
`ClickHouse.config.clone.assign(...)` so pooled connections keep your configured settings.

```ruby
require 'connection_pool'

ClickHouse.connection = ConnectionPool.new(size: 2) do
  config = ClickHouse.config.clone.assign(url: 'http://replica.example.com')
  ClickHouse::Connection.new(config)
end

ClickHouse.connection.with do |conn|
  conn.tables
end
```

## Using with Rails

```yml
# config/click_house.yml

default: &default
  url: http://localhost:8123
  timeout: 60
  open_timeout: 3

development:
  database: ecliptic_development
  <<: *default

test:
  database: ecliptic_test
  <<: *default

production:
  <<: *default
  database: ecliptic_production
```

```ruby
# config/initializers/click_house.rb

ClickHouse.config do |config|
  config.logger = Rails.logger
  config.assign(Rails.application.config_for('click_house'))
end
```

```ruby
# lib/tasks/click_house.rake
namespace :click_house do
  task prepare: :environment do
    @environments = Rails.env.development? ? %w[development test] : [Rails.env]
  end

  task drop: :prepare do
    @environments.each do |env|
      config = ClickHouse.config.clone.assign(Rails.application.config_for('click_house', env: env))
      connection = ClickHouse::Connection.new(config)
      connection.drop_database(config.database, if_exists: true)
    end
  end

  task create: :prepare do
    @environments.each do |env|
      config = ClickHouse.config.clone.assign(Rails.application.config_for('click_house', env: env))
      connection = ClickHouse::Connection.new(config)
      connection.create_database(config.database, if_not_exists: true)
    end
  end
end
```

Prepare the ClickHouse database:

```bash
rake click_house:drop click_house:create
```

If your are using SQL Database in Rails, you can manage ClickHouse migrations
using `ActiveRecord::Migration` mechanism

```ruby
class CreateAdvertVisits < ActiveRecord::Migration[6.0]
  def up
    ClickHouse.connection.create_table('visits', engine: 'MergeTree(date, (account_id, advert_id), 512)') do |t|
      t.UInt16   :account_id
      t.UInt16   :user_id
      t.Date     :date
    end
  end

  def down
    ClickHouse.connection.drop_table('visits')
  end
end
```

## Using with ActiveRecord

if you use `ActiveRecord`, you can use the ORM query builder by using fake models
(empty tables must be present in the SQL database `create_table :visits`)

```ruby
class ClickHouseRecord < ActiveRecord::Base
  self.abstract_class = true

  class << self
    def agent
      ClickHouse.connection
    end

    def insert(*argv, &block)
      agent.insert(table_name, *argv, &block)
    end

    def select_one
      agent.select_one(current_scope.to_sql)
    end

    def select_value
      agent.select_value(current_scope.to_sql)
    end

    def select_all
      agent.select_all(current_scope.to_sql)
    end

    def explain
      agent.explain(current_scope.to_sql)
    end
  end
end
````

````ruby
# FAKE MODEL FOR ClickHouse
class Visit < ClickHouseRecord
  scope :with_os, -> { where.not(os_family_id: nil) }
end

Visit.with_os.select('COUNT(*) as counter').group(:ipv4).select_all
#=> [{ 'ipv4' => 1455869, 'counter' => 104 }]

Visit.with_os.select('COUNT(*)').select_value
#=> 20_345_678

Visit.where(user_id: 1).select_one
#=> { 'ipv4' => 1455869, 'user_id' => 1 }
````

## Using with RSpec

You can clear the data table before each test with RSpec

```ruby
RSpec.configure do |config|
  config.before(:each, truncate_click_house: true) do
    ClickHouse.connection.truncate_tables
  end
end
```

```ruby
RSpec.describe Api::MetricsCountroller, truncate_click_house: true do
  it { }
  it { }
end
```

## Development

```bash
make dockerize
rspec
rubocop
```

To test against another ClickHouse version or port, set `CLICKHOUSE_VERSION` and
`CLICKHOUSE_PORT` (defaults: `22.9` and `8123`):

```bash
CLICKHOUSE_VERSION=26.3 CLICKHOUSE_PORT=28123 docker compose -p ch-26-3 up -d
CLICKHOUSE_PORT=28123 rspec
```

Specs tagged `:offline` don't need a server. They skip the database setup hooks, and
full-stack ones answer requests with canned responses through Faraday's test adapter
(`stub_clickhouse` in `spec/support/stub_clickhouse.rb`):

```bash
rspec --tag offline
```
