package Cpanel::Config::userdata::Aliases;

# cpanel - Cpanel/Config/userdata/Aliases.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::userdata::Aliases - determine aliases for userdata files

=head1 SYNOPSIS

    my $vh_aliases = Cpanel::Config::userdata::Aliases::get_for_user('bob')

=head1 DESCRIPTION

The “userdata” files store all of the aliases that will be included in
each vhost’s F<httpd.conf> C<ServerAlias> directive … with the exception of
SSL service subdomains, which aren’t stored in the “userdata” files.

=cut

#----------------------------------------------------------------------

use Cpanel::Config::WebVhosts      ();
use Cpanel::WebVhosts::AutoDomains ();
use Cpanel::Config::userdata::Load ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $vh_aliases = get_for_user( $USERNAME )

Gets the expected aliases for each of a given user’s web vhosts.

The return is a reference to a hash whose keys are vhost names; each value
is a reference to an array of the corresponding vhost’s expected aliases as
the “userdata” files store them.

=cut

sub get_for_user {
    my ($username) = @_;

    my $vhconf = Cpanel::Config::WebVhosts->load($username);

    my %park_sub = $vhconf->addon_domains();

    my %sub_parks;
    for my $park ( keys %park_sub ) {
        push @{ $sub_parks{ $park_sub{$park} } }, $park;
    }

    my %created_lookup = map { $_ => 1 } (
        $vhconf->main_domain(),
        $vhconf->subdomains(),
        $vhconf->parked_domains(),
        $vhconf->addon_domains(),
    );

    my %vh_aliases;

    for my $vhname ( $vhconf->main_domain(), $vhconf->subdomains() ) {
        my @zone_names;

        my @parks;
        if ( $vhname eq $vhconf->main_domain() ) {
            @parks = $vhconf->parked_domains();
            push @zone_names, $vhname;
        }
        else {
            @parks = $sub_parks{$vhname} ? @{ $sub_parks{$vhname} } : ();
        }

        push @zone_names, @parks;

        my @expected_aliases = @parks;

        for my $label ( Cpanel::WebVhosts::AutoDomains::ON_ALL_CREATED_DOMAINS() ) {
            for my $created_name ( $vhname, @parks ) {
                next if 0 == index( $created_name, '*' );
                push @expected_aliases, "$label.$created_name";
            }
        }

        # Add things that only go on domains that have separate zones.
        # Created domains can override these; for example, if
        # the user actually creates “mail.example.com”, then there
        # won’t be an auto-created alias in the vhost.
        for my $label ( Cpanel::WebVhosts::AutoDomains::WEB_SUBDOMAINS_FOR_ZONE() ) {
            for my $zname (@zone_names) {
                next if $created_lookup{"$label.$zname"};

                push @expected_aliases, "$label.$zname";
            }
        }

        #----------------------------------------------------------------------

        my $fix_ud_guard_cr;

        my $uddata = Cpanel::Config::userdata::Load::load_userdata_domain_or_die(
            $username,
            $vhname,
        );

        if ( $uddata->{'ipv6'} ) {
            for my $zname (@zone_names) {
                next if $created_lookup{"ipv6.$zname"};

                # We don't do this for addon domains
                next if $park_sub{$zname};

                push @expected_aliases, "ipv6.$zname";
            }
        }

        $vh_aliases{$vhname} = \@expected_aliases;
    }

    return \%vh_aliases;
}

1;
