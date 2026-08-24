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
print ui_table_row(hlink($text{'config_bantime'}, 'config_bantime'), ui_textbox('ban_duration', $defaults->{'bantime_seconds'} // '', 15));
print ui_table_row(hlink($text{'config_findtime'}, 'config_findtime'), ui_textbox('find_time', $defaults->{'findtime_seconds'} // '', 15));
print ui_table_row(hlink($text{'config_maxretry'}, 'config_maxretry'), ui_textbox('max_retries', $defaults->{'maxretry'} // '', 15));
print ui_table_row(hlink($text{'config_allow'}, 'config_allow'), ui_textarea('allowlist', join("\n", @{$defaults->{'allow'} || []}), 5, 60));
print ui_table_row(hlink($text{'config_escalate_enabled'}, 'config_escalate_enabled'), ui_yesno_radio('escalation_enabled', $defaults->{'escalate_enabled'} ? 1 : 0));
print ui_table_row(hlink($text{'config_escalate_factor'}, 'config_escalate_factor'), ui_textbox('escalation_multiplier', $escalation->{'factor'} // '', 15));
print ui_table_row(hlink($text{'config_backend'}, 'config_backend'), ui_textbox('backend', $defaults->{'backend'} // '', 30));
print ui_table_row(hlink($text{'config_socket'}, 'config_socket'), ui_textbox('socket', $effective->{'paths'}->{'socket'} // '', 60));
print ui_table_row(hlink($text{'config_state_dir'}, 'config_state_dir'), ui_textbox('state_dir', $effective->{'paths'}->{'state_dir'} // '', 60));
print ui_table_end();
my $running = minsec::service_state()->{'running'};
print minsec::action_button($text{'config_restart'}, 'save', 'restart') if ($running && minsec::check_acl('service'));
print minsec::action_button($text{'config_save'}, 'save', 'only');
print ui_form_end();
ui_print_footer('index.cgi', $text{'index_dashboard'});
