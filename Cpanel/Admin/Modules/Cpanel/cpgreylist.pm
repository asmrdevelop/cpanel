
# cpanel - Cpanel/Admin/Modules/Cpanel/cpgreylist.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::cpgreylist;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Exception                    ();
use Cpanel::GreyList::Client             ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();

sub _actions {
    return qw( DOMAIN_GREYLIST_ENABLE DOMAIN_GREYLIST_DISABLE DOMAIN_GREYLIST_ENABLED );
}

sub DOMAIN_GREYLIST_DISABLE {
    my ( $self, @domains ) = @_;
    my $user = $self->get_caller_username();

    _validate_domains( $user, \@domains );
    my $client = Cpanel::GreyList::Client->new();
    return $client->enable_opt_out_for_domains( \@domains );
}

sub DOMAIN_GREYLIST_ENABLE {
    my ( $self, @domains ) = @_;
    my $user = $self->get_caller_username();

    _validate_domains( $user, \@domains );
    my $client = Cpanel::GreyList::Client->new();
    return $client->disable_opt_out_for_domains( \@domains );
}

sub DOMAIN_GREYLIST_ENABLED {
    my ( $self, @domains ) = @_;
    my $user = $self->get_caller_username();

    _validate_domains( $user, \@domains );

    my $client = Cpanel::GreyList::Client->new();
    my $output;
    foreach my $domain (@domains) {
        $output->{$domain} = $client->is_greylisting_enabled($domain) ? 1 : 0;
    }
    return $output;
}

sub _validate_domains {
    my ( $user, $domains_ar ) = @_;

    foreach my $domain ( @{$domains_ar} ) {
        if ( Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain) ne $user ) {
            die Cpanel::Exception->create( 'The domain “[_1]” does not belong to “[_2]”.', [ $domain, $user ] );
        }
    }
    return 1;
}

1;
