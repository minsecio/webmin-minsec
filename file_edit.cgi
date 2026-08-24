#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%in, %text);
ReadParse();
minsec::require_acl('raw');
my ($inspection, $inspect_error) = minsec::inspect();
error(minsec::html_escape($inspect_error)) if ($inspect_error);
my $is_new = $in{'new'} ? 1 : 0;
my $type = $in{'type'} && $in{'type'} eq 'filter' ? 'filter' : 'dropin';
my $path = $in{'path'} || '';
my $kind = $is_new ? $type : minsec::discovered_file_kind($inspection, $path);
$type = $kind eq 'filter' ? 'filter' : 'dropin';
my $title = $is_new ?
	($type eq 'filter' ? $text{'files_create_filter'} : $text{'files_create_dropin'}) :
	($kind eq 'filter' ? $text{'files_edit_filter'} :
	 $kind eq 'main' ? $text{'files_edit_main'} : $text{'files_edit_dropin'});
my $help_prefix = $type eq 'filter' ? 'filter' : 'dropin';
my $content = '';
if (!$is_new) {
	my ($safe_path, $path_error) = minsec::allowed_file_path($path, $inspection, 0, $type);
	error(minsec::html_escape($path_error)) if ($path_error);
	open(my $handle, '<', $safe_path) || error("Cannot read file: ".minsec::html_escape($!));
	local $/;
	$content = <$handle>;
	close($handle);
}
ui_print_header('', $title, '', 'intro', 1, 1);
print minsec::navigation('files');
print ui_form_start('save_file.cgi', 'post');
print ui_hidden('new', $is_new);
print ui_hidden('type', $type);
print ui_hidden('path', $path) if (!$is_new);
print ui_table_start($title, 'width=100%', 2);
print ui_table_row(hlink($text{'files_filename'}, $help_prefix.'_filename'),
	$is_new ? ui_textbox('name', '', 45) : minsec::html_escape($path));
print ui_table_row(hlink($text{'files_toml'}, $help_prefix.'_toml'),
	ui_textarea('content', $content, 30, 100));
print ui_table_end();
print minsec::action_button($text{'config_save'}, 'operation', 'save');
print minsec::action_button($text{'config_restart'}, 'operation', 'restart') if (minsec::service_state()->{'running'} && minsec::check_acl('service'));
print minsec::action_button($text{'files_delete'}, 'operation', 'delete') if (!$is_new);
print ui_form_end();
ui_print_footer('files.cgi', $text{'files_title'});
