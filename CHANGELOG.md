# Unreleased

# 2.2.0

## Changed
* [#19](https://github.com/tenjin/click_house/pull/19) `config.global_params` now also
  apply to `select_*` and other GET queries, as the README describes; before, only
  `execute` and `insert` sent them. Settings there such as `session_id` or output formats
  now affect selects too. Per-request `query:` params to `Connection#get` take precedence,
  including over `send_progress_in_http_headers`
* [#6](https://github.com/tenjin/click_house/pull/6) Raise `ClickHouse::DbException` for
  failed JSON and CSV queries on ClickHouse 23.5 and later, which raised
  `JSON::ParserError`/`Oj::ParseError` because the server sends error text with an
  `application/json` content type
* [#25](https://github.com/tenjin/click_house/pull/25) `execute`, `insert` and `post`
  send `config.database` or the `database:` argument over a `:database` key in
  `global_params` or `params:`, as selects already did. With `database: nil`, such as in
  `databases` and `create_database`, they no longer send the `:database` from
  `global_params`
* [#21](https://github.com/tenjin/click_house/pull/21) For a `ResultSet` built by hand,
  `to_a` no longer raises `KeyError` for a row key that isn't in `meta` (it leaves the
  value unchanged), and a row missing a column gets that column's cast of `nil` instead of
  staying without it, e.g. `TypeError` for an integer column

## Fixed
* [#17](https://github.com/tenjin/click_house/pull/17) Fix `ArgumentError` on every JSON
  response when using json gem 3.x. json 3 also rejects unknown or string keys in
  `config.json_load_options`
* [#18](https://github.com/tenjin/click_house/pull/18) Fix `NoMethodError` for
  `CGI.parse` in the logging middleware when no other gem loads the `cgi` library, e.g.
  Faraday 2.14+ with ActiveSupport 8+, or Ruby 4.0

## Added
* [#24](https://github.com/tenjin/click_house/pull/24) `config.parse_floats` parses JSON
  numbers as `Float` instead of `BigDecimal` and sends
  `output_format_json_quote_decimals=1`, so Decimal columns arrive as strings and keep
  their precision. Off by default. `readonly=1` users need the setting in their profile
* [#13](https://github.com/tenjin/click_house/pull/13) `config.adapter` also accepts an
  array of a Faraday adapter and its arguments, e.g. `config.adapter = [:test, stubs]`

## Performance
* [#20](https://github.com/tenjin/click_house/pull/20) Cast query results faster by
  resolving each column's casters once per result instead of for every value, with
  identical results
* [#21](https://github.com/tenjin/click_house/pull/21) Skip casting columns whose JSON
  values are already the cast result (String, FixedString, UUID, Enum, and Nullable,
  LowCardinality or Array of those)
* [#16](https://github.com/tenjin/click_house/pull/16) Cast `DateTime` and `DateTime64`
  values faster (about 2x for columns with a time zone) with identical results

# 2.1.2
* Cast `Date`, `DateTime` and `DateTime64` values with `strptime` instead of `parse`, and
  look up each column's type arguments once, for faster casting
* `Date`, `DateTime` and `DateTime64` casting expects ClickHouse's default
  `date_time_output_format`; values in `iso` format now raise `ArgumentError`
* Casters no longer pass `nil` through for columns that aren't `Nullable`: Integer casting
  raises `TypeError`, IPv4/IPv6 casting raises `IPAddr::AddressFamilyError`, String
  casting returns `""`, and Integer serialization writes `0`. `LowCardinality` passes
  `nil` on to its inner type

# 2.1.1
* Fix logging with symbolized keys JSON
* Unknown formats return raw `Response::ResultSelt` like regular JSON query
* Added methods `statistics`, `summary`, `headers` and `types` to `Response::ResultSet`

# 2.1.0
* `ClickHouse.connection.insert` now returns `ClickHouse::Response::Summary` object
  with methods `headers`, `summary`, `written_rows`, `written_bytes`, etc... 
* `ClickHouse.connection.insert(columns: ["id"], values: [1])` now uses `JSONCompactEachRow` by default
  (to increase JSON serialization speed)
* Methods `insert_rows` and `insert_compact` added to `connection`
* Added ability to pass object directly to insert like:
  `ClickHouse.connection.insert("table", {id: 1})` or
  `ClickHouse.connection.insert("table", [{id: 1})]` (for ruby < 3.0 use `ClickHouse.connection.insert("table", [{id: 1}], {})`)
* 🔥 Added config option `json_serializer` (one of `ClickHouse::Serializer::JsonSerializer`, `ClickHouse::Serializer::JsonOjSerializer`)
* 🔥 Added config option `symbolize_keys`
* 🔥 Added type serialization for INSERT statements, example below:

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

# 2.0.0
* Fixed `Bigdecimal` casting with high precision
* Added nested `type casting like Array(Array(Array(Nullable(T))))`
* Added `Map(T1, T2)` support
* Added `Tuple(T1, T2)` support
* Added support for `Faraday` v1 and v2
* Added support for `Oj` parser
* Time types return `Time` class instead of `DateTime` for now

# 1.6.3
* [PR](https://github.com/shlima/click_house/pull/38) Add option format for insert
* [PR](https://github.com/shlima/click_house/pull/34) Support X-ClickHouse-Exception-Code header
* [ISSUE](https://github.com/shlima/click_house/issues/33) Fix parameterized types parsing
* Added LowCardinality DDL support
* Fixed body logging with POST queries

# 1.6.2
* [PR](https://github.com/shlima/click_house/pull/31) Add rows_before_limit_at_least to ResultSet
* [PR](https://github.com/shlima/click_house/pull/29) Force JSON format by using "default_format" instead of modifying the query

# 1.6.1
* [PR](https://github.com/shlima/click_house/pull/26) call logging middleware when an error is raised

# 1.6.0
* [PR](https://github.com/shlima/click_house/pull/19) handle value returned as nil in float and integer types (case of Aggregate Function Combinators) 
* [PR](https://github.com/shlima/click_house/pull/18) Fix Faraday deprecation

# 1.5.0
* add support for 'WITH TOTALS' modifier in response
* send SQL in GET request's body [#12](https://github.com/shlima/click_house/pull/12)
* add support of 'WITH TOTALS' on a resulting set

# 1.4.0
* fix decimal type casting [#11](https://github.com/shlima/click_house/issues/11)

# 1.3.9
* add `ClickHouse.connection.add_index`, `ClickHouse.connection.drop_index`

# 1.3.8
* fix `DateTime` casting for queries like `ClickHouse.connection.select_value('select NOW()')` 
* fix resulting set console inspection

# 1.3.7
* specify required ruby version [#10](https://github.com/shlima/click_house/issues/10)

# 1.3.6
* fix ruby 2.7 warning `maybe ** should be added to the call` on `ClickHouse.connection.databases`

# 1.3.5
* added `ClickHouse.connection.explain("sql")` 

# 1.3.4
* added `ClickHouse.type_names(nullable: false)`
* fixed `connection#create_table` column definitions
* `ClickHouse.add_type` now handles Nullable types automatically

# 1.3.3
* fix logger typo

# 1.3.2
* fix null logger for windows users

# 1.3.1
* added request [headers](https://github.com/shlima/click_house/pull/8) support

# 1.3.0
* added support for IPv4/IPv6 types

# 1.2.7
* rubocop version bump

# 1.2.6
* Datetime64 field type support [#3](https://github.com/shlima/click_house/pull/3)
