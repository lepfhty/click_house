# frozen_string_literal: true

RSpec.describe ClickHouse::Response::ResultSet, :offline do
  def result_set(columns, rows)
    described_class.new(
      config: ClickHouse.config,
      meta: columns.map { |name, type| { 'name' => name, 'type' => type } },
      data: rows,
      summary: nil
    )
  end

  describe '#to_a' do
    it 'casts nested containers, maps and tuples' do
      columns = {
        'id' => 'UInt64',
        'amount' => 'Nullable(Decimal(18, 4))',
        'grid' => 'Array(Array(UInt8))',
        'events' => "Map(LowCardinality(String), Array(Nullable(DateTime('UTC'))))",
        'tuple' => 'Tuple(IPv4, Nullable(Date), Nullable(String))'
      }
      rows = [
        {
          'id' => '18446744073709551615',
          'amount' => BigDecimal('1.2345'),
          'grid' => [[1, 2], []],
          'events' => { 'open' => ['2024-01-02 03:04:05', nil] },
          'tuple' => ['127.0.0.1', '2022-01-02', nil]
        },
        { 'id' => '1', 'amount' => nil, 'grid' => [], 'events' => {}, 'tuple' => ['10.0.0.1', nil, 'x'] }
      ]

      expect(result_set(columns, rows).to_a).to eq(
        [
          {
            'id' => 18_446_744_073_709_551_615,
            'amount' => BigDecimal('1.2345'),
            'grid' => [[1, 2], []],
            'events' => { 'open' => [Time.find_zone('UTC').local(2024, 1, 2, 3, 4, 5), nil] },
            'tuple' => [IPAddr.new('127.0.0.1'), Date.new(2022, 1, 2), nil]
          },
          { 'id' => 1, 'amount' => nil, 'grid' => [], 'events' => {}, 'tuple' => [IPAddr.new('10.0.0.1'), nil, 'x'] }
        ]
      )
    end

    it 'coerces nil maps and tuples like Hash() and Array()' do
      rows = [{ 'm' => nil, 't' => nil }]

      expect(result_set({ 'm' => 'Map(String, UInt8)', 't' => 'Tuple(UInt8, String)' }, rows).to_a)
        .to eq([{ 'm' => {}, 't' => [] }])
    end

    it 'casts scalars with type arguments' do
      rows = [{ 't' => '2024-01-02 03:04:05.678' }]

      expect(result_set({ 't' => "DateTime64(3, 'UTC')" }, rows).to_a.first.fetch('t'))
        .to eq(Time.find_zone('UTC').local(2024, 1, 2, 3, 4, Rational(5678, 1000)))
    end

    it 'raises IndexError for a tuple with more values than types' do
      expect { result_set({ 't' => 'Tuple(UInt8)' }, [{ 't' => [1, 2] }]).to_a }.to raise_error(IndexError)
    end

    it 'casts the data rows in place' do
      rows = [{ 'n' => '1' }]
      set = result_set({ 'n' => 'UInt64' }, rows)

      expect(set.to_a).to be(rows)
      expect(set.data).to eq([{ 'n' => 1 }])
    end

    it 'leaves keys that are not in meta unchanged' do
      expect(result_set({ 'n' => 'UInt64' }, [{ 'n' => '1', 'extra' => 'x' }]).to_a).to eq([{ 'n' => 1, 'extra' => 'x' }])
    end

    it 'casts a built-in container with no inner type' do
      expect { result_set({ 'n' => 'Nullable' }, [{ 'n' => 1 }]).to_a }.to raise_error(NoMethodError, /caster/)
    end

    it 'returns values of no-op columns without casting them' do
      tags = %w[a b]
      name = +'x'
      rows = [{ 'name' => name, 'tags' => tags, 'note' => nil, 'days' => ['2022-01-02'] }]
      columns = {
        'name' => 'LowCardinality(String)', 'tags' => 'Array(String)',
        'note' => 'Nullable(String)', 'days' => 'Array(Date)'
      }
      row = result_set(columns, rows).to_a.first

      expect(row.fetch('name')).to be(name)
      expect(row.fetch('tags')).to be(tags)
      expect(row.fetch('note')).to be_nil
      expect(row.fetch('days')).to eq([Date.new(2022, 1, 2)])
    end

    it 'does not parse types for an empty result' do
      expect(ClickHouse::Ast::Parser).not_to receive(:new)

      expect(result_set({ 'n' => 'UInt64' }, []).to_a).to eq([])
    end

    context 'with a custom container type' do
      let(:wrapper) do
        Class.new(ClickHouse::Type::BaseType) do
          def container?
            true
          end

          def cast_each(value, *)
            { 'wrapped' => yield(value) }
          end
        end
      end

      around do |example|
        ClickHouse.add_type('Wrapped', wrapper.new)
        example.run
      ensure
        ClickHouse.types.delete('Wrapped')
      end

      it 'casts through the registered cast_each' do
        expect(result_set({ 'w' => 'Wrapped(UInt8)' }, [{ 'w' => '7' }]).to_a).to eq([{ 'w' => { 'wrapped' => 7 } }])
      end
    end

    context 'with a custom subclass of a no-op caster' do
      around do |example|
        ClickHouse.add_type('Shout', Class.new(ClickHouse::Type::StringType) { define_method(:cast) { |value, *| value.upcase } }.new)
        example.run
      ensure
        ClickHouse.types.delete('Shout')
      end

      it 'still casts the column' do
        expect(result_set({ 's' => 'Array(Shout)' }, [{ 's' => ['a'] }]).to_a).to eq([{ 's' => ['A'] }])
      end
    end

    context 'with a custom container type that has no inner type' do
      let(:wrapper) do
        Class.new(ClickHouse::Type::BaseType) do
          def container?
            true
          end

          def cast_each(value, *)
            value.nil? ? nil : yield(value)
          end
        end
      end

      around do |example|
        ClickHouse.add_type('Bare', wrapper.new)
        example.run
      ensure
        ClickHouse.types.delete('Bare')
      end

      it 'raises only when a value reaches the missing type' do
        expect(result_set({ 'b' => 'Bare' }, [{ 'b' => nil }]).to_a).to eq([{ 'b' => nil }])
        expect { result_set({ 'b' => 'Bare' }, [{ 'b' => 1 }]).to_a }.to raise_error(NoMethodError, /caster/)
      end
    end
  end
end
