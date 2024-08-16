
# cpanel - Whostmgr/Email.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Email;

use strict;
use warnings;

use Cpanel::UserDatastore::Init ();
use Cpanel::Locale::Lazy 'lh';
use Cpanel::PwCache                  ();
use Cpanel::Config::LoadCpUserFile   ();
use Cpanel::Validate::EmailLocalPart ();
use Cpanel::Email::Accounts          ();
use Cpanel::Exception                ();

# our for tests
my $cache_file_name = 'email_count_by_domain';

sub list_pops_for {
    my $user         = shift || die lh()->maketext('Please specify a [asis,user].') . "\n";
    my $domain       = shift;
    my $userdomains  = shift;
    my $user_homedir = Cpanel::PwCache::gethomedir($user) || die lh()->maketext( 'The “[_1]” user does not exist.', $user ) . "\n";

    require Cpanel::AccessIds::ReducedPrivileges;

    # WARNING | This information is being loaded from an untrusted source under the user's control.
    # WARNING | It must only be used in conjunction with a trusted list of domains belonging to
    # WARNING | the user.
    my ( $untrusted_pops_info, $_manage_err );
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        $user,
        sub {
            undef $Cpanel::user;
            ( $untrusted_pops_info, $_manage_err ) = Cpanel::Email::Accounts::manage_email_accounts_db(
                'event'   => 'fetch',
                'no_disk' => 1,
                ( $domain ? ( 'matchdomain' => $domain ) : () )
            );
            die $_manage_err if $_manage_err;
            return 1;
        }
    );

    my $this_user_domains_ar;

    # Because we don't trust the data above, load the list of domains from a trusted source
    if ($userdomains) {
        $this_user_domains_ar = [ grep { $userdomains->{$_} eq $user } keys %$userdomains ];
    }
    else {
        my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load_or_die($user);
        $this_user_domains_ar = $cpuser_ref->{'DOMAINS'} || [];
        push @$this_user_domains_ar, $cpuser_ref->{'DOMAIN'};
    }

    # Important: Only use the untrusted data as a reference for the list of local parts,
    # not for the list of domains.
    my @trusted_pops_list;
    for my $domain (@$this_user_domains_ar) {
        for my $acct ( keys %{ $untrusted_pops_info->{$domain}{accounts} || {} } ) {
            if (
                ( length $acct && $acct !~ tr/a-zA-Z0-9!#\$\-=?^_{}~//c )    # If it only contains safe chars skip the expensive validate
                || Cpanel::Validate::EmailLocalPart::is_valid($acct)
            ) {
                push @trusted_pops_list, $acct . '@' . $domain;
            }
        }
    }

    # At this point, we are returning verified data that the caller should be able to trust
    # does not contain any email addresses with bogus domains, even if the account in question
    # had manipulated their email_accounts.json file to misrepresent the domain list.
    return [ sort @trusted_pops_list ];
}

=head1 NAME

Whostmgr::Email

=head2 count_pops_for( user, domain )

Get the number of email accounts for a user or, optionally, that also are on a specific domain.

=head3 Arguments

=over 4

=item B<user>   - scalar - required

The username to get the email account list for

=item B<domain> - scalar - optional

The domain to match when returning email accounts count. The function will only return the count for
email accounts that match this domain if specified. If this parameter is not passed, then all the
email accounts for the user will be counted.

=back

=head3 Returns

An integer that represents the count of email accounts for a particular user and possibly for a particular domain owned by that user.

=head3 Exceptions

=over 4

=item I<Cpanel::Exception::MissingParameter>

thrown if $user is not passed

=item I<Cpanel::Exception::DomainOwnership>

if $domain is passed, but the $user doesn't own that domain this exception will be thrown

=item I<Cpanel::Exception::UserNotFound>

if the $user does not have a homedirectory this will be thrown

=back

=cut

sub count_pops_for {
    my ( $user, $domain ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] ) if !length $user;

    if ( length $domain ) {
        require Cpanel::AcctUtils::DomainOwner::Tiny;
        if ( Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => q{} } ) ne $user ) {
            my $is_mail_and_user_owns_main_domain = 0;
            if ( index( $domain, 'mail.' ) == 0 ) {
                $is_mail_and_user_owns_main_domain = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( substr( $domain, 5 ), { 'default' => q{} } ) eq $user;
            }

            if ( !$is_mail_and_user_owns_main_domain ) {
                die Cpanel::Exception::create( 'DomainOwnership', 'The account “[_1]” does not own the domain “[_2]”.', [ $user, $domain ] );
            }
        }
    }

    return count_pops_for_without_ownership_check( $user, $domain );
}

=head2 count_pops_for_without_ownership_check( user, domain )

count_pops_for_without_ownership_check is the same as count_pops_for without
a check to validate that $user owns the $domain.

Note that L<Cpanel::Email::Count> has logic to count email accounts
as a user.

=cut

sub count_pops_for_without_ownership_check {
    my ( $user, $domain ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] ) if !length $user;

    my ( $user_gid, $homedir ) = ( Cpanel::PwCache::getpwnam_noshadow($user) )[ 3, 7 ];

    $homedir or die Cpanel::Exception::create( 'UserNotFound', [ name => $user ] );

    my $user_datastore_directory = Cpanel::UserDatastore::Init::initialize($user);
    my $cache_path               = $user_datastore_directory . "/$cache_file_name";

    if ( open my $fh, '<', $cache_path ) {
        my $cache_path_mtime = ( stat $fh )[9];

        my $user_email_cache_mtime = _get_mtime_for_user_email_cache( $user, $homedir );
        if ( $user_email_cache_mtime && $user_email_cache_mtime <= $cache_path_mtime ) {
            require Cpanel::JSON;
            my $cache_file_data = eval { Cpanel::JSON::LoadFile($fh) };
            warn "JSON load error ($cache_path): $@" if $@;

            return _return_count( $cache_file_data, $domain ) if ref $cache_file_data eq 'HASH';
        }
    }
    elsif ( $! != _ENOENT() ) {
        warn "open(< $cache_path): $!";
    }

    require Cpanel::Transaction::File::JSON;
    my $rw_transaction = Cpanel::Transaction::File::JSON->new(
        path        => $cache_path,
        permissions => 0644,
    );

    my $email_addresses = list_pops_for($user);

    my %domains_seen = ( total => 0 );
    for my $email (@$email_addresses) {
        my ( $email_account, $email_domain ) = split( m{\@}, $email, 2 );

        $domains_seen{$email_domain}++;
        $domains_seen{'total'}++;
    }

    $rw_transaction->set_data( \%domains_seen );

    my ( $status, $message ) = $rw_transaction->save_and_close();
    warn "save $cache_path: $message" if !$status;

    return _return_count( \%domains_seen, $domain );
}

sub _return_count {
    my ( $domain_hash, $domain ) = @_;

    if ( length $domain ) {
        return $domain_hash->{$domain} || 0;
    }
    else {
        return $domain_hash->{'total'} || 0;
    }
}

# No need to reduce privs to do a stat here
sub _get_mtime_for_user_email_cache {
    my ( $user, $homedir ) = @_;

    my $path  = Cpanel::Email::Accounts::get_email_accounts_file_path($homedir);
    my $mtime = ( stat($path) )[9];
    return $mtime;
}

sub _ENOENT { return 2; }
1;
