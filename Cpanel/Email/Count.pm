package Cpanel::Email::Count;

# cpanel - Cpanel/Email/Count.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Email::Count

=head1 SYNOPSIS

    my $count = Cpanel::Email::Count::count_pops();

    $count = Cpanel::Email::Count::count_pops( no_validate => 1 );

    $count = Cpanel::Email::Count::count_pops_by_domain(
        domain => 'example.com',
    );

=head1 DESCRIPTION

Here live functions to count email accounts as a user.

Note that L<Whostmgr::Email> has logic to do the same as root.

=cut

#----------------------------------------------------------------------

use Cpanel                  ();    # PPI NO PARSE - pending CPANEL-27165
use Cpanel::Security::Authz ();
use Cpanel::LoadFile        ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $count = count_pops( %OPTS )

Counts up all of the current cPanel user’s email (“pop”) accounts.

%OPTS are C<no_validate> and/or C<transaction_obj> (or neither).
See C<Cpanel::Email::Accounts::manage_email_accounts_db()> for
what these do.

A suitable exception is thrown on failure.

=cut

sub count_pops {
    my (%opts) = @_;

    Cpanel::Security::Authz::verify_not_root();

    local $@;

    my $count;
    warn if !eval {
        $count = Cpanel::LoadFile::load_if_exists( $Cpanel::homedir . '/.cpanel/email_accounts_count' );
        1;
    };

    return $count // __count_pops( %opts{ 'no_validate', 'transaction_obj' } );
}

#----------------------------------------------------------------------

=head2 $count = count_pops_by_domain( %OPTS )

Like C<count_pops()> but restricted to a specific domain.

%OPTS must include a C<domain> and may optionally include the
parameters that C<count_pops()> accepts.

A suitable exception is thrown on failure.

=cut

sub count_pops_by_domain {
    my (%opts) = @_;

    die 'Need “domain”!' if !length $opts{'domain'};

    Cpanel::Security::Authz::verify_not_root();

    return __count_pops( %opts{ 'domain', 'no_validate', 'transaction_obj' } );
}

sub __count_pops {
    my (%OPTS) = @_;

    require Cpanel::Email::Accounts;
    my ( $popaccts_ref, $_manage_err ) = Cpanel::Email::Accounts::manage_email_accounts_db(
        'event'           => 'fetch',
        'no_validate'     => int( $OPTS{'no_validate'} || 0 ),
        'no_disk'         => 1,
        'transaction_obj' => $OPTS{'transaction_obj'},
    );

    my $pops = 0;

    if ( !$popaccts_ref ) {
        warn $_manage_err if defined $_manage_err;
    }
    elsif ( length $OPTS{'domain'} ) {
        if ( my $domain_hr = $popaccts_ref->{ $OPTS{'domain'} } ) {
            if ( ref $domain_hr->{'accounts'} ) {
                $pops = keys %{ $domain_hr->{'accounts'} };
            }
        }
    }
    else {
        for my $domain_hr ( values %{$popaccts_ref} ) {
            if ( $domain_hr && ref $domain_hr->{'accounts'} ) {
                $pops += ( scalar keys %{ $domain_hr->{'accounts'} } );
            }
        }
    }

    return $pops;
}

1;
