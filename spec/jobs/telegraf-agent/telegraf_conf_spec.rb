require 'rspec'
require 'rspec/collection_matchers'
require 'json'
require 'toml'
require 'bosh/template/test'

describe 'telegraf-agent job' do
  let(:release) { Bosh::Template::Test::ReleaseDir.new(File.join(File.dirname(__FILE__), '../../..')) }
  let(:job) { release.job('telegraf-agent') }

  describe 'postgresql config' do
    let(:template) { job.template('config/telegraf.conf') }
    let(:influx) { { 'url' => 'influx_url', 'database' => 'influx_db' } }
    let(:postgres_link) do
      Bosh::Template::Test::Link.new(
        name: 'postgres',
        instances: [Bosh::Template::Test::LinkInstance.new(address: 'mock_ip_addr')],
        properties: {
          'databases' => {
            'databases' => [
              {
                'name' => 'db_name_one'
              }
            ],
            'roles' => [
              {
                'name' => 'role_name_one',
                'password' => 'role_pw_one'
              }
            ],
            'port' => 123
          }
        }
      )
    end

    it 'configures influxdb correctly' do
      rendered = template.render('influxdb' => influx)
      config = TOML::Parser.new(rendered).parsed

      expect(config['outputs']['influxdb'][0]['urls']).to contain_exactly('influx_url')
      expect(config['outputs']['influxdb'][0]['database']).to eq('influx_db')
      expect(config['inputs']).to be_nil
    end

    it 'configures postgresql correctly' do
      rendered = template.render(
        'influxdb' => influx,
        'inputs' => {
          'postgresql' => {
            'address' => 'psql_addr'
          }
        }
      )
      config = TOML::Parser.new(rendered).parsed

      postgresql_conf = config['inputs']['postgresql']
      expect(postgresql_conf).to have(1).entries
      expect(postgresql_conf[0]['address']).to eq('psql_addr')
      expect(postgresql_conf[0]['databases']).to be_empty
      expect(postgresql_conf[0]['ignored_databases']).to be_empty
    end

    it 'configures postgresql correctly when address and link given' do
      rendered = template.render(
        {
          'influxdb' => influx,
          'inputs' => {
            'postgresql' => {
              'address' => 'psql_addr'
            }
          }
        },
        consumes: [postgres_link]
      )
      config = TOML::Parser.new(rendered).parsed

      postgresql_conf = config['inputs']['postgresql']
      expect(postgresql_conf).to have(1).entries
      expect(postgresql_conf[0]['address']).to eq('psql_addr')
      expect(postgresql_conf[0]['databases']).to be_empty
      expect(postgresql_conf[0]['ignored_databases']).to be_empty

      postgresql_extensible = config['inputs']['postgresql_extensible']
      expect(postgresql_extensible).to be_nil
    end

    it 'configures postgresql correctly when only link given' do
      rendered = template.render(
        {
          'influxdb' => influx,
          'inputs' => {
            'postgresql' => {
              'ignored_databases' => [],
              'databases' => []
            }
          }
        },
        consumes: [postgres_link]
      )
      config = TOML::Parser.new(rendered).parsed

      postgresql_conf = config['inputs']['postgresql']
      expect(postgresql_conf).to have(1).entries
      expect(postgresql_conf[0]['address']).to eq('postgres://role_name_one:role_pw_one@mock_ip_addr/db_name_one')
      expect(postgresql_conf[0]['databases']).to be_empty
      expect(postgresql_conf[0]['ignored_databases']).to be_empty
    end

    it 'configures postgresql_extensible correctly given queries' do
      rendered = template.render(
        {
          'influxdb' => influx,
          'inputs' => {
            'postgresql_extensible' => {
              'address' => 'extensible_ip_addr',
              'databases' => [],
              'outputaddress' => 'extensible_output_addr',
              'queries' => [
                {
                  'measurement' => 'm1',
                  'query' => 'q1',
                  'version' => 1,
                  'withdbname' => false,
                  'tags' => []
                },
                {
                  'measurement' => 'm2',
                  'query' => 'q2',
                  'version' => 2,
                  'withdbname' => true,
                  'tags' => ['q2_tag']
                }
              ]
            }
          }
        },
        consumes: [postgres_link]
      )

      config = TOML::Parser.new(rendered).parsed

      postgresql_ext_conf = config['inputs']['postgresql_extensible']
      expect(postgresql_ext_conf).to have(1).entries
      expect(postgresql_ext_conf[0]['address']).to eq('extensible_ip_addr')

      queries = postgresql_ext_conf[0]['query']
      expect(queries).to have(2).entries

      expect(queries[0]['measurement']).to eq('m1')
      expect(queries[0]['sqlquery']).to eq('q1')
      expect(queries[0]['version']).to eq(1)
      expect(queries[0]['withdbname']).to eq(false)
      expect(queries[0]['tagvalue']).to be_empty

      expect(queries[1]['measurement']).to eq('m2')
      expect(queries[1]['sqlquery']).to eq('q2')
      expect(queries[1]['version']).to eq(2)
      expect(queries[1]['withdbname']).to eq(true)
      expect(queries[1]['tagvalue']).to eq('q2_tag')
    end

    it 'does not add postgresql_extensible to config if no queries provided' do
      rendered = template.render(
        {
          'influxdb' => influx,
          'inputs' => {
            'postgresql_extensible' => {
              'databases' => [],
              'outputaddress' => 'extensible_output_addr',
              'queries' => []
            }
          }
        },
        consumes: [postgres_link]
      )

      config = TOML::Parser.new(rendered).parsed

      postgresql_ext_conf = config['inputs']['postgresql_extensible']
      expect(postgresql_ext_conf).to be_nil
    end
  end
end
