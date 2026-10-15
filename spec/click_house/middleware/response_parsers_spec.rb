RSpec.describe 'response parsers', :offline do
  let(:config) { ClickHouse.config }

  def env(status:, body:, headers:)
    Faraday::Env.from(status: status, body: body, response_headers: Faraday::Utils::Headers.new(headers))
  end

  {
    ClickHouse::Middleware::ParseJson => ['application/json; charset=UTF-8', '{"a": 1}', { 'a' => 1 }, 'JSON.parse'],
    ClickHouse::Middleware::ParseJsonOj => ['application/json; charset=UTF-8', '{"a": 1}', { 'a' => 1 }, 'Oj.load'],
    ClickHouse::Middleware::ParseCsv => ['text/csv; charset=UTF-8', "1,2\n", [%w[1 2]], 'CSV.parse']
  }.each do |klass, (content_type, body, parsed, parser_call)|
    describe klass do
      subject do
        klass.new(nil, options: { config: config }, content_type: Regexp.new(Regexp.escape(content_type.split(';').first)))
      end

      let(:error_text) { 'Code: 60. DB::Exception: Table default.foo does not exist. (UNKNOWN_TABLE)' }
      let(:parser) { subject && Object.const_get(parser_call.split('.').first) }
      let(:parse_method) { parser_call.split('.').last.to_sym }
      let(:success_headers) { { 'content-type' => content_type } }

      def success(body)
        env(status: 200, body: body, headers: success_headers)
      end

      context 'when successful' do
        it 'parses the body' do
          response = success(body)
          subject.on_complete(response)
          expect(response.body).to eq(parsed)
        end

        it 'hands a body surrounded by whitespace to the parser as is' do
          padded = " \t\r\n#{body}\r\n\t "
          expect(parser).to receive(parse_method).with(padded, any_args).and_return(:parsed)
          response = success(padded)
          subject.on_complete(response)
          expect(response.body).to eq(:parsed)
        end
      end

      context 'when the body is blank' do
        {
          'empty' => '',
          'spaces' => '   ',
          'a tab' => "\t",
          'a newline' => "\n",
          'CRLF' => "\r\n",
          'a vertical tab and form feed' => "\v\f",
          'NUL bytes' => "\0\0",
          'mixed whitespace and NUL' => " \0\t\r\n\v\f\0 ",
          'binary-encoded whitespace' => " \r\n".b
        }.each do |description, blank|
          it "skips parsing a body of #{description}" do
            expect(parser).not_to receive(parse_method)
            response = success(blank.dup)
            subject.on_complete(response)
            expect(response.body).to eq(klass == ClickHouse::Middleware::ParseCsv ? nil : blank)
          end
        end
      end

      context 'when the body is not blank' do
        {
          'non-breaking space' => " ",
          'ideographic space' => "　",
          'leading NUL before content' => "\0x",
          'binary content' => "\xff ".b
        }.each do |description, content|
          it "hands a body of #{description} to the parser" do
            expect(parser).to receive(parse_method).with(content, any_args).and_return(:parsed)
            response = success(content.dup)
            subject.on_complete(response)
            expect(response.body).to eq(:parsed)
          end
        end
      end

      context 'when whitespace surrounds invalid UTF-8' do
        it 'raises ArgumentError before parsing' do
          expect(parser).not_to receive(parse_method)
          response = success(" \xff ".dup.force_encoding(Encoding::UTF_8))
          expect { subject.on_complete(response) }.to raise_error(ArgumentError, /invalid byte sequence/)
        end
      end

      # String#strip's result and errors for these differ between Ruby versions, so the
      # expected outcome comes from strip itself.
      context 'when the body has an encoding a regexp can not scan' do
        def outcome
          [:returned, yield]
        rescue StandardError => e
          [e.class, e.message]
        end

        {
          'invalid UTF-8 after content' => "x\xff".dup.force_encoding(Encoding::UTF_8),
          'invalid UTF-8 inside JSON' => "{\"a\":\"\xff\"}".dup.force_encoding(Encoding::UTF_8),
          'invalid UTF-8 before content' => "\xff x".dup.force_encoding(Encoding::UTF_8),
          'UTF-16LE whitespace' => ' '.encode(Encoding::UTF_16LE),
          'UTF-16LE content' => 'x'.encode(Encoding::UTF_16LE),
          'UTF-32BE whitespace' => "\t".encode(Encoding::UTF_32BE)
        }.each do |description, body|
          it "matches String#strip for #{description}" do
            expected = outcome { body.dup.strip.empty? }
            expect(outcome { subject.blank_body?(success(body.dup)) }).to eq(expected)
          end
        end
      end

      context 'when the body is nil' do
        it 'raises NoMethodError' do
          expect { subject.on_complete(success(nil)) }.to raise_error(NoMethodError)
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
