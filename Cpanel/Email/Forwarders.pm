package Cpanel::Email::Forwarders;

# cpanel - Cpanel/Email/Forwarders.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Email::Forwarders

=head1 SYNOPSIS

    my $count = Cpanel::Email::Forwarders::count();

=head1 DESCRIPTION

This module abstracts over how users’ email forwarders are stored.

=head1 TODO

Migrate more functionality from Cpanel::API::Email into this module.

=cut

#----------------------------------------------------------------------

use Cpanel                 ();
use Cpanel::Email::Aliases ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $count = count();

Returns the number of email forwarders that the cPanel user
has configured.

=cut

sub count {
    die 'No $Cpanel::user!'    if !$Cpanel::user;
    die 'No @Cpanel::DOMAINS!' if !@Cpanel::DOMAINS;

    my $count = 0;

    foreach my $domain (@Cpanel::DOMAINS) {
        if ( index( $domain, '..' ) > -1 || $domain =~ tr{/}{} ) {
            warn "Invalid domain in \@Cpanel::DOMAINS ($Cpanel::user): “$domain”";
            next;
        }

        next if !Cpanel::Email::Aliases::domain_has_entry($domain);

        my $aliases_obj = Cpanel::Email::Aliases->new( domain => $domain );

        for my $alias ( $aliases_obj->get_aliases() ) {
            for my $dest ( $aliases_obj->get_destinations($alias) ) {
                next if $dest !~ tr<@><>;
                next if $dest =~ m<\s>;
                next if $dest eq $Cpanel::user;

                $count++;
            }
        }
    }

    return $count;
}

1;
