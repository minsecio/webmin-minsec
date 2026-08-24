#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%in, %text);
ReadParse();
minsec::require_acl('filters');
my $name = $in{'name'} || '';
error('Invalid filter name') if ($name !~ /\A[A-Za-z0-9_.-]+\z/);
my ($inspection, $inspect_error) = minsec::inspect();
error(minsec::html_escape($inspect_error)) if ($inspect_error);
my ($filter) = grep { ($_->{'name'} || '') eq $name } @{$inspection->{'filters'} || []};
error('Unknown filter') if (!$filter);
my $policy = $filter->{'effective_policy'} || {};
ui_print_header('', 'Filter Policy: '.minsec::html_escape($name), '', 'intro', 1, 1);
print minsec::navigation('filters');
print ui_form_start('save_filter.cgi', 'post');
print ui_hidden('name', $name);
print ui_table_start('Filter Policy', 'width=100%', 2);
print ui_table_row($text{'filters_enabled'}, ui_yesno_radio('enabled', $filter->{'enabled'} ? 1 : 0));
print ui_table_row('Maximum retries', ui_textbox('max_retries', $policy->{'maxretry'} // '', 15));
print ui_table_row('Find time', ui_textbox('find_time', $policy->{'findtime_seconds'} // '', 15));
print ui_table_row('Ban duration', ui_textbox('ban_duration', $policy->{'bantime_seconds'} // '', 15));
print ui_table_end();
print minsec::action_button($text{'config_save'}, 'operation', 'save');
if (minsec::service_state()->{'running'} && minsec::check_acl('service')) {
	print minsec::action_button($text{'config_restart'}, 'operation', 'restart');
}
print ui_form_end();
print ui_form_start('test_filter.cgi', 'post', 'enctype="multipart/form-data"');
print ui_hidden('name', $name);
print ui_table_start('Test Filter', 'width=100%', 2);
print ui_table_row('Server-side log file', ui_textbox('log_file', '', 70));
print ui_table_row('Or upload a log file', ui_upload('upload', 60));
print ui_table_end();
print minsec::action_button('Run Test', 'operation', 'test');
print ui_form_end();
ui_print_footer('filters.cgi', $text{'filters_title'});
