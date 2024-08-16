package Whostmgr::Authz;

# cpanel - Whostmgr/Authz.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Authz

=head1 DESCRIPTION

This module implements useful logic for authorization (i.e., confirming
access to requested resources for a user who is already authenticated)
in WHM.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Config::HasCpUserFile        ();
use Cpanel::Exception                    ();
use Cpanel::Reseller                     ();
use Cpanel::Validate::FilesystemNodeName ();
use Whostmgr::AcctInfo::Owner            ();
use Whostmgr::ACLS                       ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=cut

#overridden in tests
sub _get_domain_owner {
    my ($domain) = @_;

    my $owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner(
        $domain,
        { 'default' => undef },
    );

    # Undef owner could be because $domain is the system’s hostname
    # (or maybe a former hostname whose DNS zone still exists).
    # In that case we need to query dnsadmin to see if the hostname
    # zone exists. BUT, don’t bother with that unless we’re an admin
    # only admins have access to “system”-owned zones.
    if ( !defined($owner) && Whostmgr::ACLS::hasroot() ) {
        require Cpanel::DnsUtils::Exists;
        if ( Cpanel::DnsUtils::Exists::domainexists($domain) ) {
            $owner = 'system';
        }
    }

    return $owner;
}

#overridden_in_tests
*_user_owns_user = \&Whostmgr::AcctInfo::Owner::checkowner;

#Returns 1 if:
#
#   - REMOTE_USER is the passed-in account name
#   - REMOTE_USER owns the passed-in account name
#   - REMOTE_USER has root access *and* the account exists
#
#die()s otherwise
#
sub verify_account_access {
    my ($username) = @_;

    $username //= '';

    my $operator = $ENV{'REMOTE_USER'} || die "Need \$ENV{REMOTE_USER}!\n";

    # If remote user is root, and the account being acted on is also root, don't bother with ACL or ownership check.
    # ACLs might not have been initialized.
    return 1 if $operator eq 'root' && $username eq 'root';

    if ( Whostmgr::ACLS::hasroot() ) {

        # Resellers with 'all' ACL (hasroot) should bypass ownership check for root, because root does not have a cpuser file.
        return 1 if $username eq 'root';

        #We need to check for this separately because W::AU::O::checkowner()
        #does not check account existence
        my $ok = Cpanel::Validate::FilesystemNodeName::is_valid($username);

        $ok &&= ( Cpanel::Config::HasCpUserFile::has_cpuser_file($username) || Cpanel::Reseller::isreseller($username) );

        return 1 if $ok;

        die Cpanel::Exception::create( 'UserNotFound', [ name => $username ] );
    }
    else {
        return 1 if _account_access_yn( $operator, $username );
    }

    die Cpanel::Exception->create( 'You do not have access to an account named “[_1]”.', [$username] );
}

sub _account_access_yn {
    my ( $owner_maybe, $username ) = @_;

    return 1 if $username eq $owner_maybe;
    return 1 if _user_owns_user( $owner_maybe, $username );

    return 0;
}

=head2 $domain_owner = verify_domain_existence_and_access( $DOMAIN )

Returns the domain owner if:

=over

=item * The passed-in domain exists.

=item * REMOTE_USER is the passed-in domain’s owner

=item * REMOTE_USER owns the passed-in domain’s owner

=item * REMOTE_USER has root access

=back

C<die()>s otherwise.

=cut

sub verify_domain_existence_and_access ($domain) {
    return _verify_domain_access( $domain, 1 );
}

=head2 $domain_owner = verify_domain_access( $DOMAIN )

B<IMPORTANT:> Avoid in new code. See below.

Like C<verify_domain_existence_and_access()> but B<may> not
C<die()> in the event of domain nonexistence. Specifically,
if $DOMAIN isn’t a local domain, REMOTE_USER is an administrator, and …

=over

=item * … $DOMAIN is a I<valid> domain (that just doesn’t exist locally),
this returns C<root>.

=item * … $DOMAIN is an I<invalid> domain, B<BEHAVIOR> B<IS> B<UNDEFINED>.
This is why you should B<AVOID> creating new calls to this function. If you
need to tolerate domain nonexistence, then please create a new function.

=back

=cut

sub verify_domain_access ($domain) {
    return _verify_domain_access($domain);
}

sub _verify_domain_access ( $domain, $throw_on_root_nonexist_yn = undef ) {    ## no critic qw(ManyArgs) - mis-parse

    my $operator = $ENV{'REMOTE_USER'} || die 'Need $ENV{REMOTE_USER}!';
    my $has_root = Whostmgr::ACLS::hasroot();

    $domain //= '';

    my $d_owner = _get_domain_owner($domain);
    if ( !defined($d_owner) && $has_root ) {
        my $die_yn = $throw_on_root_nonexist_yn;

        $die_yn ||= do {
            require Cpanel::Validate::FilesystemNodeName;

            # We should not check for existence; that should happen outside
            # this function. Here we only do a basic validity check for
            # historical reasons in case any callers expect this validation.
            # Callers should not assume that this function will continue to
            # do the FilesystemNodeName check in the future.
            #
            !Cpanel::Validate::FilesystemNodeName::is_valid($domain);
        };

        if ($die_yn) {
            die Cpanel::Exception::create( 'DomainDoesNotExist', [ name => $domain ] );
        }
        $d_owner = 'root';
    }
    if ($d_owner) {
        return $d_owner if $has_root || _account_access_yn( $operator, $d_owner );
    }

    #It's also possible that the domain doesn't exist on the server, but we shouldn't disclose that in this context (nonroot) either.
    die Cpanel::Exception->create( 'You do not have access to a domain named “[_1]”.', [$domain] );
}

1;
