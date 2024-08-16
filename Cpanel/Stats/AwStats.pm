package Cpanel::Stats::AwStats;

# cpanel - Cpanel/Stats/AwStats.pm                 Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf8

=head1 NAME

C<Cpanel::Stats::AwStats>

=head1 DESCRIPTION

This package provides some helper to manipulate awstats file
from a cPanel account.

=head1 SYNOPSIS

    use Cpanel::Stats::AwStats ();

    my $files_per_domain = Cpanel::Stats::AwStats::get_txt_files_per_domain()
        or Cpanel::Stats::AwStats::get_txt_files_per_domain( "${Cpanel::homedir}/tmp/awstats" );

    # Check the awstats files and return them per domain

    # {
    #   'mydomain.test' => [
    #       '/home/mytestuser/tmp/awstats/ssl/awstats022023.mydomain.test.txt',
    #       '/home/mytestuser/tmp/awstats/ssl/awstats032023.mydomain.test.txt',
    #       '/home/mytestuser/tmp/awstats/ssl/awstats042023.mydomain.test.txt'
    #   ],
    #   'subdomain.tld.main.tld' => [
    #       '/home/mytestuser/tmp/awstats/awstats012023.subdomain.tld.main.tld.txt',
    #   ]
    # }

=head1 FUNCTIONS

=head2 get_txt_files_per_domain ( $dir = undef )

Check the awstats files and return them per domain as a HashRef.
When no files are found returns 'undef'.

By default, when '$dir' is unset, try to use "${Cpanel::homedir}/tmp/awstats"

    {
      'mydomain.test' => [
          '/home/mytestuser/tmp/awstats/ssl/awstats022023.mydomain.test.txt',
          '/home/mytestuser/tmp/awstats/ssl/awstats032023.mydomain.test.txt',
          '/home/mytestuser/tmp/awstats/ssl/awstats042023.mydomain.test.txt'
      ],
      'subdomain.tld.main.tld' => [
          '/home/mytestuser/tmp/awstats/awstats012023.subdomain.tld.main.tld.txt',
      ]
    }

=cut

sub get_txt_files_per_domain ( $dir = undef ) {    # ...

    $dir //= $Cpanel::homedir . '/tmp/awstats' if defined $Cpanel::homedir;
    return                                     if !defined $dir || !-d $dir;

    my %domains;
    foreach my $check_dir ( $dir, "$dir/ssl" ) {
        opendir( my $dir_dh, $check_dir ) or next;
        while ( my $file = readdir $dir_dh ) {
            next if $file !~ m/\.txt$/;
            next if $file !~ m/^awstats\d/a;
            next if !-f $check_dir . '/' . $file || -z _;

            # log files for wildcard domains will include the domain in _wildcard_.domain.tld format
            if ( $file =~ m/^awstats\d+\.((?:_wildcard_)?[a-z0-9\-\.]+)\.txt$/ ) {
                my $domain = lc $1;
                push @{ $domains{$domain} }, "$check_dir/$file";
            }
        }
        closedir $dir_dh;
    }

    return unless scalar keys %domains;
    return \%domains;
}

1;

