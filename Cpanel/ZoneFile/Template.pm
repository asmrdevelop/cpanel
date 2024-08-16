package Cpanel::ZoneFile::Template;

# cpanel - Cpanel/ZoneFile/Template.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::Owner ();
use Cpanel::StatCache        ();

my $logger;

sub _base_dir {
    return '';
}

my %_get_zone_template_file_cache;

sub get_zone_template_file {
    my (%opts) = @_;

    return unless defined $opts{type};

    ## CPANEL-11206: 'Modify Account' passes in the new owner as 'user',
    ##   so that the new owner's custom zone templates are used
    $opts{user} ||= $ENV{'REMOTE_USER'} || '';
    my $user = $opts{user};
    $user =~ tr{/}{}d if length $user;

    my $cache_key = $opts{type} . '___' . $user;

    return $_get_zone_template_file_cache{$cache_key} if $_get_zone_template_file_cache{$cache_key};

    my @basenames;
    if ( $user && $user ne 'root' ) {

        # 1 - user ( do we really want to check for the user ? )
        #   added for backward compatibility
        push( @basenames, $user );

        # 2 - reseller
        my $owner = Cpanel::AcctUtils::Owner::getowner($user);
        push( @basenames, $owner ) if ( $owner && $owner ne $user );
    }

    # 3 - root
    push( @basenames, 'root' );

    my $base = _base_dir();

    # add default dir prefix and template suffix
    my @candidates =
      map { $base . '/var/cpanel/zonetemplates/' . $_ . '_' . $opts{type} } @basenames;

    # 4 - template
    push @candidates, $base . '/var/cpanel/zonetemplates/' . $opts{type};

    # 5 - default value ( should exists )
    push @candidates, $base . '/usr/local/cpanel/etc/zonetemplates/' . $opts{type};

    # search for a valid candidate
    foreach my $candidate (@candidates) {
        return ( $_get_zone_template_file_cache{$cache_key} = $candidate ) if Cpanel::StatCache::cachedmtime($candidate);
    }

    return;
}

#
#   Return a hash indicating whether the preferred file of each type
#   include settings to turn on SPF validation of emails
#
sub template_enforces_spf {
    my ($reseller) = @_;

    my %result;

    for my $template_type (qw{ simple standard standardvirtualftp }) {
        $result{$template_type} = undef;
        my $path = get_zone_template_file( user => $reseller, type => $template_type );
        if ($path) {
            if ( open my $ztemp, '<', $path ) {
                while ( my $line = <$ztemp> ) {
                    $line =~ s{;.*}{};    # Strip comments
                    if ( $line =~ /\bIN\s+(?:TXT|SPF)\s+"?(v=spf1\s*[^"]*)"?/ ) {
                        $result{$template_type} = $1;
                        last;
                    }
                }
            }
            else {
                require Cpanel::Logger;
                $logger ||= Cpanel::Logger->new();
                $logger->warn("Could not open zone template file '$template_type'");
            }
        }
    }
    return ( wantarray ? %result : \%result );
}

1;
