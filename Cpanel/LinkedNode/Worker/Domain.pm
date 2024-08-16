package Cpanel::LinkedNode::Worker::Domain;

# cpanel - Cpanel/LinkedNode/Worker/Domain.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Worker::Domain

=head1 SYNOPSIS

    if ( my $hostname = get_worker_alias( 'Mail', 'example.com' ) ) {

        # … do “Mail”-type things for “example.com” on $hostname …
    }

=head1 DESCRIPTION

Administrator tools for the intersection between worker nodes and domains.

=cut

#----------------------------------------------------------------------

use Cpanel::AcctUtils::DomainOwner::Tiny ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $hostname = get_worker_alias( $WORKER_TYPE, $DOMAIN )

Determines which cPanel user owns the domain $DOMAIN and returns
the alias (if any) of the linked node that that cPanel user has
configured as a remote worker node of type $WORKER_TYPE (e.g., C<Mail>).

If there is no such alias, undef is returned.

An exception propagates if $DOMAIN is not owned by a cPanel user
and is not the system’s hostname, or if an error prevents
reading the user’s configuration.

=cut

sub get_worker_alias {
    my ( $worker_type, $domain ) = @_;

    my $sysuser = _get_domain_owner($domain);

    if ($sysuser) {
        require Cpanel::Config::LoadCpUserFile;
        require Cpanel::LinkedNode::Worker::Storage;

        my $userconf      = Cpanel::Config::LoadCpUserFile::load_or_die($sysuser);
        my $node_token_ar = Cpanel::LinkedNode::Worker::Storage::read( $userconf, $worker_type );

        if ($node_token_ar) {
            return $node_token_ar->[0];
        }
    }
    else {
        require Cpanel::Hostname;
        if ( $domain ne Cpanel::Hostname::gethostname() ) {
            die "No cPanel user appears to own the domain “$domain”!";
        }
    }

    return undef;
}

sub _get_domain_owner {
    my ($domain) = @_;

    return Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { default => undef } );
}

1;
