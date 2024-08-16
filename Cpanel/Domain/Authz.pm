package Cpanel::Domain::Authz;

# cpanel - Cpanel/Domain/Authz.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Domain::Authz

=head1 SYNOPSIS

    # Returns truthy (assuming “bob.com” is bob’s)
    Cpanel::Domain::Authz::user_controls_domain( 'bob', 'bob.com' );

    # Returns falsy
    Cpanel::Domain::Authz::user_controls_domain( 'bob', 'google.com' );

=cut

use Cpanel::Exception ();
use Cpanel::Set       ();
use Cpanel::WebVhosts ();

=head1 FUNCTIONS

=head2 user_controls_domain( $USER, $DOMAIN )

Returns a boolean that indicates whether $DOMAIN is under $USER’s
control.  This factors in $USER’s automatically-created subdomains
(e.g., C<www>) as well as service (formerly proxy) subdomains.

Note that this does NOT consider a user to own, e.g., C<*.foo.com>
unless that wildcard domain is itself one of the user’s owned domains.
Ownership of C<foo.com> does NOT imply ownership of C<*.foo.com>. (If that
logic is desirable here, then please create a separate function to do so,
analogous to other functions in this module.)

=cut

sub user_controls_domain {
    my ( $user, $domain ) = @_;

    # It’s somewhat unfortunate that we have to go to web-specific logic
    # to determine this function’s result, but it is what it is.
    for my $d_hr ( Cpanel::WebVhosts::list_ssl_capable_domains($user) ) {
        return 1 if $d_hr->{'domain'} eq $domain;
    }

    return 1 if _user_has_ddns( $user, $domain );

    return 0;
}

#----------------------------------------------------------------------

=head2 validate_user_control_of_domains( $USERNAME, \@DOMAINS )

Returns empty if the user controls B<ALL> of the given @DOMAINS.
Throws an exception otherwise.

Each @DOMAINS member is assumed to be unique within the array.

Note that this will consider the user to control a given wildcard domain
ONLY if the wildcard domain itself is one of the user’s owned domains. For
example, for this function to consider the user to control C<*.foo.com>, it
is not sufficient merely to control C<foo.com>; the user MUST own the wildcard
domain itself. (If you want ownership of C<foo.com> to imply ownership of
C<*.foo.com>, then look at
C<validate_user_control_of_domains__allow_wildcard()>.

=cut

sub validate_user_control_of_domains {
    my ( $username, $domains_ar ) = @_;

    my $non_owned_ar = get_unowned_domains( $username, $domains_ar );

    if (@$non_owned_ar) {
        _die_because_unowned($non_owned_ar);
    }

    return;
}

#----------------------------------------------------------------------

=head2 $unowned_ar = get_unowned_domains( $USERNAME, \@DOMAINS )

Like C<validate_user_control_of_domains()>, but this just returns the unowned
domains (as an array reference) rather than throwing an exception.

If the user owns all domains in @DOMAINS, the returned array reference
will be empty.

The same caveat about wildcard domains as described for
C<validate_user_control_of_domains()> applies to this function.
See C<get_unowned_domains__allow_wildcard()> if you want the “looser”
validation as described above.

=cut

sub get_unowned_domains {
    my ( $username, $domains_ar ) = @_;

    my @ssl_capable_domains = Cpanel::WebVhosts::list_ssl_capable_domains($username);
    $_ = $_->{'domain'} for @ssl_capable_domains;

    my @non_owned = Cpanel::Set::difference(
        $domains_ar,
        \@ssl_capable_domains,
    );

    # We don’t need to read dynamic DNS unless there are domains whose
    # ownership we can’t account for yet.
    if (@non_owned) {
        my @ddns = map { $_->domain() } _read_user_ddns($username);

        @non_owned = Cpanel::Set::difference(
            \@non_owned,
            \@ddns,
        );
    }

    return \@non_owned;
}

#----------------------------------------------------------------------

=head2 validate_user_control_of_domains__allow_wildcard( $USERNAME, \@DOMAINS )

Similar to C<validate_user_control_of_domains()> but considers that a user
controls, e.g., C<*.foo.com> by virtue of controlling C<foo.com>.

Use this when, for example, validating TLS certificate purchase orders.

=cut

sub validate_user_control_of_domains__allow_wildcard {
    my ( $username, $domains_ar ) = @_;

    my $non_owned_ar = get_unowned_domains__allow_wildcard( $username, $domains_ar );

    if (@$non_owned_ar) {
        _die_because_unowned($non_owned_ar);
    }

    return;
}

#----------------------------------------------------------------------

=head2 $unowned_ar = get_unowned_domains__allow_wildcard( $USERNAME, \@DOMAINS )

Similar to C<get_unowned_domains()> but considers that a user
controls, e.g., C<*.foo.com> by virtue of controlling C<foo.com>.

Use this when, for example, validating TLS certificate purchase orders.

=cut

sub get_unowned_domains__allow_wildcard {
    my ( $username, $domains_ar ) = @_;

    my %original_domains;
    for my $csr_domain (@$domains_ar) {
        my $verification_domain = ( $csr_domain =~ s<\A\*\.><>r );
        push @{ $original_domains{$verification_domain} }, $csr_domain;
    }

    my @verification_domains = keys %original_domains;

    my $unowned_ar = get_unowned_domains(
        $username,
        \@verification_domains,
    );

    return [ map { @$_ } @original_domains{@$unowned_ar} ];
}

#----------------------------------------------------------------------

sub _read_user_ddns ($username) {
    my $id_entry_hr;

    if ($>) {
        require Cpanel::WebCalls::Datastore::ReadAsUser;
        $id_entry_hr = Cpanel::WebCalls::Datastore::ReadAsUser::read_all();
    }
    else {
        require Cpanel::WebCalls::Datastore::Read;
        $id_entry_hr = Cpanel::WebCalls::Datastore::Read->read_for_user($username);
    }

    return grep { $_->isa('Cpanel::WebCalls::Entry::DynamicDNS') } values %$id_entry_hr;
}

sub _user_has_ddns ( $username, $domain ) {
    return grep { $domain eq $_->domain() } _read_user_ddns($username);
}

sub _die_because_unowned {
    my ($domains_ar) = @_;

    die Cpanel::Exception::create( 'DomainOwnership', 'You do not own [numerate,_1,the following domain,any of the following domains]: [join,~, ,_2].', [ 0 + @$domains_ar, $domains_ar ], { domains => $domains_ar } );
}

1;
