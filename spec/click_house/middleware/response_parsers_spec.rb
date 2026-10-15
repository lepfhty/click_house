RSpec.describe 'response parsers', :offline do
  let(:config) { ClickHouse.config }

  def env(status:, body:, headers:)
    Faraday::Env.from(status: status, body: body, response_headers: Faraday::Utils::Headers.new(headers))
  end

  {
    ClickHouse::Middleware::ParseJson => ['application/json; charset=UTF-8', '{"a": 1}', { 'a' => 1 }],
    ClickHouse::Middleware::ParseJsonOj => ['application/json; charset=UTF-8', '{"a": 1}', { 'a' => 1 }],
    ClickHouse::Middleware::ParseCsv => ['text/csv; charset=UTF-8', "1,2\n", [%w[1 2]]]
  }.each do |klass, (content_type, body, parsed)|
    describe klass do
      subject do
        klass.new(nil, options: { config: config }, content_type: Regexp.new(Regexp.escape(content_type.split(';').first)))
      end

      let(:error_text) { 'Code: 60. DB::Exception: Table default.foo does not exist. (UNKNOWN_TABLE)' }

      context 'when successful' do
        it 'parses the body' do
          response = env(status: 200, body: body, headers: { 'content-type' => content_type })
          subject.on_complete(response)
          expect(response.body).to eq(parsed)
        end
      end

      context 'when the server returns an error with a matching content type' do
        it 'leaves the error text untouched' do
          response = env(
            status: 404,
            body: error_text,
            headers: { 'content-type' => content_type, 'x-clickhouse-exception-code' => '60' }
          )
          subject.on_complete(response)
          expect(response.body).to eq(error_text)
        end
      end

      context 'when the exception header arrives with a 200 status' do
        it 'leaves the body untouched' do
          response = env(
            status: 200,
            body: error_text,
            headers: { 'content-type' => content_type, 'x-clickhouse-exception-code' => '60' }
          )
          subject.on_complete(response)
          expect(response.body).to eq(error_text)
        end
      end
    end
  end
end
