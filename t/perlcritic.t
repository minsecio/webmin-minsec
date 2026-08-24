#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Find;

BEGIN {
	eval { require Perl::Critic; 1 } or plan skip_all => 'Perl::Critic not installed';
}

my @files;
find(sub {
	return if (-d $_);
	return if ($File::Find::name =~ m{/(?:lang|help)/});
	push(@files, $File::Find::name) if (/\.(?:pl|cgi|t)\z/);
}, '.');
my $critic = Perl::Critic->new('-profile' => '.perlcriticrc');
foreach my $file (sort(@files)) {
	my @violations = $critic->critique($file);
	is(scalar(@violations), 0, "$file perlcritic");
	diag(join('', @violations)) if (@violations);
}
done_testing();
