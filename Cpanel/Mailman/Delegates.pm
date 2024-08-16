package Cpanel::Mailman::Delegates;

# cpanel - Cpanel/Mailman/Delegates.pm             Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
use cPstrict;

use Cpanel             ();
use Cpanel::LoadModule ();

use Cpanel::Locale::Lazy 'lh';

=head1 NAME

Cpanel::Mailman::Delegates

=head1 DESCRIPTION

This module is a breakout of _has_delegated_mailinglists from Cpanel::API::Email
so that we can call it in the context of ExpVar Multipass (which is mostly
so that conditionals evaluated in webmail for this pass, but it probably is
also more efficient than just calling the API "in template".

=head1 FUNCTIONS

=head2 has_delegated_mailman_lists($delegate)

Given $delegate, check whether there are any delegated mailman lists for the user.

Returns a list with two elements:

=over

=item * status - Whether the check was able to be completed successfully.

=item * info - The result of the check. If status is true, then this is a boolean indicating whether there are any
delegated mailman lists. If status is false, then this is the error message.

=back

=cut

sub has_delegated_mailman_lists {
    my ($delegate) = @_;

    if ( !length $delegate ) {
        return ( 0, lh()->maketext( "The “[_1]” parameter is required.", 'delegate' ) );
    }

    if ( $delegate eq $Cpanel::user ) {
        return ( 1, 0 );
    }

    my $delegate_domain = ( split( m{\@}, $delegate, 2 ) )[1];

    if ( !length $delegate_domain ) {
        return ( 0, lh()->maketext( "The “[_1]” parameter must be in email address format.", 'delegate' ) );
    }

    if ( !grep { $_ eq $delegate_domain } @Cpanel::DOMAINS ) {
        return ( 0, lh()->maketext( '“[_1]” is not a domain that you control.', $delegate_domain ) );
    }

    # Try readonly first
    Cpanel::LoadModule::load_perl_module('Cpanel::Email::PrivsReader');
    my $privdb = eval { local $SIG{'__DIE__'}; local $SIG{'__WARN__'}; Cpanel::Email::PrivsReader->new( 'domain' => $delegate_domain ); };

    # Try read-write second (we may need to create the db)
    if ( !$privdb ) {
        require Cpanel::Email::Privs;
        $privdb = eval { Cpanel::Email::Privs->new( 'domain' => $delegate_domain ); };
        if ($@) {
            return ( 0, $@ );
        }
    }

    my $has_delegated_lists = $privdb->has_delegated_mailman_lists($delegate);

    if ( ref $privdb->can('abort') eq 'CODE' ) {
        $privdb->abort();
    }

    return ( 1, $has_delegated_lists );
}

1;
