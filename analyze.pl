#!/usr/bin/perl

use JSON;
use Data::Dumper;
use Encode qw< encode decode >;
use Getopt::Long;
use Pod::Usage;

# GLOBALS

### find zero byte files
# find . -type f -size 0|wc -l

### OPTIONS
my $analyzeRcode;
my $analyzeServfail;
my $directory;
my $limit = 0;

# get command line options
GetOptions(
    'help|?'        => \$help,
    'directory|d=s' => \$directory,
    'limit|l=i'     => \$limit,
    'rcode'         => \$analyzeRcode,
    'servfail'      => \$analyzeServfail,
    'verbose|v+'    => \$verbose,
    ) or pod2usage(2);

# help command line option
if ($help or not defined $directory) {
    pod2usage(1);
    exit;
}

main();
#pod2usage(-exitstatus => 0);
exit;

sub delimiter {
    print "----------------------\n";
}

sub main {
    # get all entries from the domain directory
    opendir DIR,"$directory/" or die "Cannot open directory: $!";
    my @all = grep { -f "$directory/$_" } readdir(DIR);
    closedir DIR;

    my %super; # all json stuff in one giant hash
    foreach my $file (@all) {
	# if ((stat($filename))[7] == 0) { next; };
	open FILE, "$directory/$file" or die "Cannot read file domain/$file: $!";
	my @j = <FILE>;
	next if not defined $j[0];
	$j = getJSON($j[0]);
	$super{$j->{'domain'}} = $j if defined $j;

	close FILE;
    }

    if ($analyzeRcode) {
	analyzeRcodes(\%super);
	delimiter;
    } elsif ($analyzeServfail) {
	analyzeServfails(\%super);
	delimiter;
    }

    print "Domains with data: ".scalar keys(%super)."\n";
}

# find values in a hash by adressing it like this "key:key2:key3"
sub findValue {
    my $hash = shift;
    my $find = shift;
    my $value;
    my $defined;
    my @keys = split (':',$find);
    @keys = map { "{'$_'}" } @keys;
    my $evalHash = '$hash->'.join('->',@keys);
    eval '$defined = defined '.$evalHash;
    return undef if $@;
    return undef if $defined eq '';
    eval '$value = '.$evalHash;
    return undef if $@;
    return $value if defined $value;
    return 1;
}

sub getJSON {
    # fix utf-8 problems and decode JSON
    my $j = shift;
    $j = encode('UTF-8', $j);
    $j = JSON->new->utf8->decode($j);
    return $j;
}

# analyze domain
sub analyzeRcodes {
    my $bighash = shift;
    my %result;

    foreach my $domain (keys(%{$bighash})) {
	$result{'A:'.findValue($bighash->{$domain},          'A:rcode')}++;
	$result{'MX:'.findValue($bighash->{$domain},         'MX:rcode')}++;
	$result{'SOA:'.findValue($bighash->{$domain},        'soa:rcode')}++;
	$result{'NSEC3PARAM:'.findValue($bighash->{$domain}, 'nsec3param:rcode')}++;
	$result{'DNSKEY:'.findValue($bighash->{$domain},     'dnskey:rcode')}++;
    }
    foreach my $key (sort keys(%result)) {
	print "$key: $result{$key}\n";
    }
}

# analyze domain
sub analyzeServfails {
    my $bighash = shift;
    my %result;

    foreach my $domain (keys(%{$bighash})) {
	if(findValue($bighash->{$domain},'A:rcode') eq 'SERVFAIL' or
	   findValue($bighash->{$domain},'MX:rcode') eq 'SERVFAIL' or
	   findValue($bighash->{$domain},'soa:rcode') eq 'SERVFAIL' or
	   findValue($bighash->{$domain},'nsec3param:rcode') eq 'SERVFAIL' or
	   findValue($bighash->{$domain},'dnskey:rcode') eq 'SERVFAIL') {
	    foreach my $rrs (findValue($bighash->{$domain},'NS:list')) {
		foreach my $ns (@$rrs) {
		    $result{$ns->{'nsdname'}}++;
		}
	    }
	}
    }
    my $i = 0;
    foreach my $key (sort { $result{$b} <=> $result{$a} } keys %result) {
	print "$key: $result{$key}\n";
	$i++;
	last if $i > $limit and $limit > 0;
    }
}
__END__

=head1 NAME

    analyze.pl

=head1 USAGE

analyze -d directory

Required argument(s):

    --directory directory    A directory with WhatWeb JSON files

Optional arguments:

    --limit value            When generating lists, limit the length to this value
    --rcode                  Analyze RCODEs
    --servfail               Toplist of name servers with SERVFAIL
    --lifetimes              Analyze RRSIG lifetimes
    --keyalgo                Analyze DNSKEY algorithms
    --iterations             Analyze NSEC3 iterations

=head1 TODO

=head1 AUTHOR

Patrik Wallström <pawal@iis.se>

=cut
