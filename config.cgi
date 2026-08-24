#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%text);
minsec::require_acl('config');
my ($inspection, $error) = minsec::inspect();
my $effective = $inspection ? ($inspection->{'effective'} || {}) : {};
my $defaults = $effective->{'defaults'} || {};
my $escalation = $defaults->{'escalate'} || {};

ui_print_header('', $text{'config_title'}, '', 'intro', 1, 1);
print minsec::navigation('config');
print ui_alert_box(minsec::html_escape($error), 'warning') if ($error);
print ui_form_start('save_config.cgi', 'post');
print ui_table_start($text{'config_title'}, 'width=100%', 2);
print ui_table_row('Default ban duration', ui_textbox('ban_duration', $defaults->{'bantime_seconds'} // '', 15));
print ui_table_row('Find time', ui_textbox('find_time', $defaults->{'findtime_seconds'} // '', 15));
print ui_table_row('Max retries', ui_textbox('max_retries', $defaults->{'maxretry'} // '', 15));
print ui_table_row('Allowlist (one CIDR per line)', ui_textarea('allowlist', join("\n", @{$defaults->{'allow'} || []}), 5, 60));
print ui_table_row('Escalation enabled', ui_yesno_radio('escalation_enabled', $defaults->{'escalate_enabled'} ? 1 : 0));
print ui_table_row('Escalation multiplier', ui_textbox('escalation_multiplier', $escalation->{'factor'} // '', 15));
print ui_table_row('Backend', ui_textbox('backend', $defaults->{'backend'} // '', 30));
print ui_table_row('Control socket', ui_textbox('socket', $effective->{'paths'}->{'socket'} // '', 60));
print ui_table_row('State directory', ui_textbox('state_dir', $effective->{'paths'}->{'state_dir'} // '', 60));
print ui_table_end();
my $running = minsec::service_state()->{'running'};
print minsec::action_button($text{'config_restart'}, 'save', 'restart') if ($running && minsec::check_acl('service'));
print minsec::action_button($text{'config_save'}, 'save', 'only');
print ui_form_end();
ui_print_footer('index.cgi', $text{'index_dashboard'});
