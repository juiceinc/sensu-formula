{% from "sensu/pillar_map.jinja" import sensu with context %}
{% from "sensu/service_map.jinja" import services with context %}
{% from "sensu/configfile_map.jinja" import files with context %}

include:
  - sensu
  - sensu.rabbitmq_conf

{% if grains['os_family'] == 'Windows' %}
/opt/sensu/bin/sensu-client.xml:
  file.managed:
    - source: salt://sensu/files/windows/sensu-client.xml
    - template: jinja
    - require:
      - pkg: sensu
sensu_install_dotnet35:
  cmd.run:
    - name: 'powershell.exe "Import-Module ServerManager;Add-WindowsFeature Net-Framework-Core"'
sensu_enable_windows_service:
  cmd.run:
    - name: 'sc create sensu-client start= delayed-auto binPath= c:\opt\sensu\bin\sensu-client.exe DisplayName= "Sensu Client"'
    - unless: 'sc query sensu-client'
{% endif %}
/etc/sensu/conf.d/client.json:
  file.serialize:
    - formatter: json
    - user: {{files.files.user}}
    - group: {{files.files.group}}
    {% if grains['os_family'] != 'Windows' %}
    - mode: 644
    {% endif %}
    - makedirs: True
    - dataset:
        client:
          name: {{ sensu.client.name }}
          address: {{ sensu.client.address }}
          subscriptions: {{ sensu.client.subscriptions }}
          safe_mode: {{ sensu.client.safe_mode }}
    - require:
      - pkg: sensu

/etc/sensu/plugins:
  file.recurse:
    - source: salt://sensu/files/plugins
    {% if grains['os_family'] != 'Windows' %}
    - file_mode: 555
    {% endif %}
    - require:
      - pkg: sensu
    - require_in:
      - service: sensu-client
    - watch_in:
      - service: sensu-client

sensu-client:
  service.running:
    - enable: True
    - require:
      - file: /etc/sensu/conf.d/client.json
      - file: /etc/sensu/conf.d/rabbitmq.json
    - watch:
      - file: /etc/sensu/conf.d/*

{% if sensu.client.embedded_ruby and grains['os_family'] != 'Windows' %}
/etc/default/sensu:
  file.replace:
    - pattern: 'EMBEDDED_RUBY=false'
    - repl: 'EMBEDDED_RUBY=true'
    - watch_in:
      - service: sensu-client
{% endif %}

{% if sensu.client.nagios_plugins %}
{{ services.nagios_plugins }}:
  pkg:
    - installed
    - require_in:
      - service: sensu-client
{% endif %}

{% if sensu.client.embedded_ruby %}
{% set gem_path = '/opt/sensu/embedded/bin/gem' %}
{% else %}
{% set gem_path = 'gem' %}
{% endif %}

{% set gem_list = salt['pillar.get']('sensu:client:install_gems', []) %}
{% for gem in gem_list %}
client_install_{{ gem }}:
  cmd.run:
    - name: {{ gem_path }} install {{ gem }} --no-ri --no-rdoc
    - unless: {{ gem_path }} list | grep -qE "^{{ gem }}\s+"
{% endfor %}

