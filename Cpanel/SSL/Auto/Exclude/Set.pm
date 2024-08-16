package Cpanel::SSL::Auto::Exclude::Set;

# cpanel - Cpanel/SSL/Auto/Exclude/Set.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Domain::Authz           ();
use Cpanel::WebVhosts::AutoDomains  ();
use Cpanel::ArrayFunc::Uniq         ();
use Cpanel::Exception               ();
use Cpanel::LoadModule              ();
use Cpanel::SSL::Auto::Exclude::Get ();
use Cpanel::Transaction::File::JSON ();

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Exclude::Set - Performs create/update/delete operations for AutoSSL domain excludes lists.

=head1 SYNOPSIS

    use Cpanel::SSL::Auto::Exclude::Set ();

    Cpanel::SSL::Auto::Exclude::Set::add_user_excluded_domains( user => 'aardvark', domains => [qw(ants.tld tasty.tld)] );

=head1 DESCRIPTION

This module is used to alter the AutoSSL domain excludes lists for users. The AutoSSL domain excludes lists are there to
disable autossl for specific domains for a user.

=cut

=head2 set_user_excluded_domains

This function sets AutoSSL excluded domains to a user's excluded config file. An excluded domain is one that
AutoSSL does not maintain the SSL certificates for.

=head3 Input

Key->Value pairs named:

=over 3

=item C<SCALAR> user

    The name of the user to set excluded domains for.

=item C<ARRAYREF> domains

    An arrayref of domains to set in the excluded list for the user.

=back

=head3 Output

=over 3

=item C<NONE> None

=back

=head3 Exceptions

This function can throw:

=over 3

=item Cpanel::Exception::MissingParameter

    Thrown if either of the parameters isn't supplied.

=item Cpanel::Exception::InvalidParameter

    Thrown if the domains_ref isn't a reference.

=item Cpanel::Exception::DomainOwnership

    Thrown if a domain in the domains_ref isn't owned by the supplied user.

=item Anything Cpanel::Transaction::File::JSON* can throw

    Check that module for more information on what can be thrown.

=back

=cut

sub set_user_excluded_domains {
    my ( $user, $domains_ref ) = _unpack_user_domain_list_args(@_);

    return _do_with_transaction(
        $user,
        sub {
            my ( $user, $data ) = @_;

            _validate_domains_list( $user, $domains_ref );

            $data->{'excluded_domains'} = $domains_ref;
        }
    );
}

=head2 add_user_excluded_domains

This function adds AutoSSL excluded domains to a user's excluded config file. An excluded domain is one that
AutoSSL does not maintain the SSL certificates for.

=head3 Input

Key->Value pairs named:

=over 3

=item C<SCALAR> user

    The name of the user to add excluded domains for.

=item C<ARRAYREF> domains

    An arrayref of domains to add to the excluded list for the user.

=back

=head3 Output

=over 3

=item C<NONE> None

=back

=head3 Exceptions

This function can throw:

=over 3

=item Cpanel::Exception::MissingParameter

    Thrown if either of the parameters isn't supplied.

=item Cpanel::Exception::InvalidParameter

    Thrown if the domains_ref isn't a reference.

=item Cpanel::Exception::DomainOwnership

    Thrown if a domain in the domains_ref isn't owned by the supplied user.

=item Anything Cpanel::Transaction::File::JSON* can throw

    Check that module for more information on what can be thrown.

=back

=cut

sub add_user_excluded_domains {
    my ( $user, $domains_ref ) = _unpack_user_domain_list_args(@_);

    #We only need to validate the new domains. The domains that
    #we already exclude should stay excluded.
    _validate_domains_list( $user, $domains_ref );

    return _do_with_transaction(
        $user,
        sub {
            my ( $user, $data ) = @_;

            my $excl_domains_ar = $data->{'excluded_domains'};

            my $domains = [ Cpanel::ArrayFunc::Uniq::uniq( @$excl_domains_ar, @{$domains_ref} ) ];

            $data->{'excluded_domains'} = $domains;
        }
    );
}

=head2 remove_user_excluded_domains

This function removes the AutoSSL excluded domains from a user's excluded config file. An excluded domain is one that
AutoSSL does not maintain the SSL certificates for.

=head3 Input

Key->Value pairs named:

=over 3

=item C<SCALAR> user

    The name of the user to remove excluded domains for.

=item C<ARRAYREF> domains

    An arrayref of domains to remove from the excluded list for the user.

=back

=head3 Output

=over 3

=item C<NONE> None

=back

=head3 Exceptions

This function can throw:

=over 3

=item Cpanel::Exception::MissingParameter

    Thrown if either of the parameters isn't supplied.

=item Cpanel::Exception::InvalidParameter

    Thrown if the domains_ref isn't a reference.

=item Anything Cpanel::Transaction::File::JSON* can throw

    Check that module for more information on what can be thrown.

=back

=cut

sub remove_user_excluded_domains {

    my ( $user, $domains_ref ) = _unpack_user_domain_list_args(@_);

    my %remove_domains = map { $_ => 1 } @{$domains_ref};

    return _do_with_transaction(
        $user,
        sub {
            my ( $user, $data ) = @_;

            _remove_user_excluded_domains( $user, $data, \%remove_domains );
        }
    );
}

sub _remove_user_excluded_domains {
    my ( $user, $data, $remove_domains ) = @_;

    $data->{'excluded_domains'} = [ grep { !$remove_domains->{$_} } @{ $data->{'excluded_domains'} } ];

    return;
}

=head2 remove_user_excluded_domains_before_non_main_domain_removal

This function removes the AutoSSL excluded domains for a non-main domain before the domain is deleted.
This should be used when deleting a parked, addon, or subdomain from cPanel. This will remove any matching
excluded domain, including those that are for autocreated domains such as mail.domain.tld.

=head3 Input

Key->Value pairs named:

=over 3

=item C<SCALAR> user

    The name of the user to remove excluded domains for.

=item C<SCALAR> remove_domain

    The domain to remove excluded domains for.

=back

=head3 Output

=over 3

=item C<NONE> None

=back

=head3 Exceptions

This function can throw:

=over 3

=item Cpanel::Exception::MissingParameter

    Thrown if either of the parameters isn't supplied.

=item die with "user's main domain not allowed!"

    If the passed in domain is a main domain.

=item Anything Cpanel::SSL::Auto::Exclude::Set::remove_user_excluded_domains can throw

=back

=cut

sub remove_user_excluded_domains_before_non_main_domain_removal {
    my (%OPTS) = @_;

    my ( $user, $remove_domain ) = @OPTS{qw( user remove_domain )};

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'user' ] )          if !$user;
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'remove_domain' ] ) if !$remove_domain;

    return _do_with_transaction(
        $user,
        sub {
            my ( $user, $data ) = @_;
            if ( my @excluded_domains = @{ $data->{excluded_domains} } ) {
                Cpanel::LoadModule::load_perl_module('Cpanel::Config::userdata::Load');
                Cpanel::LoadModule::load_perl_module('Cpanel::Config::userdata::Utils');

                my $main_userdata = Cpanel::Config::userdata::Load::load_userdata_main($user);
                die "$user’s main domain not allowed!" if $main_userdata->{main_domain} eq $remove_domain;

                #We want to identify all domains in the exclusions list that are
                #auto-created from $remove_domain, i.e., that are not user-created.

                my %domains_lookup = map { $_ => 1 } Cpanel::Config::userdata::Utils::get_all_domains_from_main_userdata($main_userdata);

                # parked or addon domains that match the proxysub.remove_domain.tld may have been added before the removal domain existed. In this case, make sure we don't remove
                # the service (formerly proxy) subdomains for one of those previously added addon or parked domains.
                my %excluded_domains_lookup = ( $remove_domain => 1, map { my $domain_w_proxy = "$_.$remove_domain"; $domains_lookup{$domain_w_proxy} ? () : ( $domain_w_proxy => 1 ) } Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_AUTO_DOMAINS() );

                #We now have a lookup hash of $remove_domain and all of its
                #auto-created domains. Here we just compare that against the
                #current exclusions list to arrive at the actual list of domains
                #to delete from the list.
                if ( my @excluded_domains_to_remove = grep { $excluded_domains_lookup{$_} } @excluded_domains ) {
                    _remove_user_excluded_domains( $user, $data, { map { $_ => 1 } @excluded_domains_to_remove } );
                }
            }
        }
    );
}

=head2 rename_user_excluded_domains

This function renames AutoSSL excluded domains in a user's config file. This is used for domain name changes on
the account.

=head3 Input

Key->Value pairs named:

=over 3

=item C<SCALAR> user

    The name of the user to rename excluded domains for.

=item C<HASHREF> domains_map

    A hashref of $current_domain_name => $new_domain_name pairs, where $current_domain_name
    is the current name of the domain and $new_domain_name is the name you want the domain to be
    renamed to.

=back

=head3 Output

=over 3

=item C<NONE> None

=back

=head3 Exceptions

This function can throw:

=over 3

=item Cpanel::Exception::MissingParameter

    Thrown if either of the parameters isn't supplied.

=item Die string '“domain_map” must be a hash reference.'

    Thrown if the domains_map isn't a reference.

=item Cpanel::Exception::DomainOwnership

    Thrown if a domain in the domains_map isn't owned by the supplied user.

=item Anything Cpanel::Transaction::File::JSON* can throw

    Check that module for more information on what can be thrown.

=back

=cut

sub rename_user_excluded_domains {
    my (%opts) = @_;

    my ( $user, $domain_map ) = @opts{ 'user', 'domain_map' };

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'user' ] )       if !$user;
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'domain_map' ] ) if !$domain_map;

    if ( ref $domain_map ne 'HASH' ) {
        die '“domain_map” must be a hash reference.';
    }

    return _do_with_transaction(
        $user,
        sub {
            my ( $user, $data ) = @_;

            my $domains = _rename_excluded_domains( $user, $data->{'excluded_domains'}, $domain_map );

            _validate_domains_list( $user, $domains );

            $data->{'excluded_domains'} = $domains;
        }
    );
}

sub _rename_excluded_domains {
    my ( $user, $excluded_domains, $domain_map ) = @_;

    my @dot_prefixes = map { $_ . '.' } Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_AUTO_DOMAINS();
    my ( @domains, @unmatched_excluded_domains );

    for my $domain (@$excluded_domains) {
        if ( $domain_map->{$domain} ) {
            push @domains, $domain_map->{$domain};
            next;
        }

        if ( my ($prefix) = grep { index( $domain, $_ ) == 0 } @dot_prefixes ) {
            my $stripped_domain = substr( $domain, length $prefix );
            if ( $domain_map->{$stripped_domain} ) {
                push @domains, $prefix . $domain_map->{$stripped_domain};
                next;
            }
        }

        push @unmatched_excluded_domains, $domain;
    }

    if ( scalar @unmatched_excluded_domains ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Debug');
        Cpanel::Debug::log_warn( "The system could not rename all AutoSSL excluded domains for the user $user. The following excluded domains could not be renamed and will be removed: " . join( ', ', @unmatched_excluded_domains ) );
    }

    return \@domains;
}

sub _unpack_user_domain_list_args {
    my (%opts) = @_;

    my ( $user, $domains_ref ) = @opts{ 'user', 'domains' };

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'user' ] )    if !$user;
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'domains' ] ) if !$domains_ref;
    if ( ref $domains_ref ne 'ARRAY' ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” must be a hash reference.', ['domains'] );
    }

    return ( $user, $domains_ref );

}

sub _do_with_transaction {
    my ( $user, $coderef ) = @_;

    if ( !-e $Cpanel::SSL::Auto::Exclude::Get::EXCLUDES_DIR ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Mkdir');

        Cpanel::Mkdir::ensure_directory_existence_and_mode( $Cpanel::SSL::Auto::Exclude::Get::EXCLUDES_DIR, 0711 );
    }

    my $transaction = Cpanel::Transaction::File::JSON->new(
        path        => scalar Cpanel::SSL::Auto::Exclude::Get::get_user_excludes_file_path($user),
        permissions => 0640,
        ownership   => [ 0, $user ],
    );

    my $data = $transaction->get_data();
    $data = {} if !$data || 'SCALAR' eq ref $data;
    $data->{'excluded_domains'} ||= [];

    try {
        $coderef->( $user, $data );
    }
    catch {
        my $err = $_;
        $transaction->close_or_die();
        local $@ = $err;
        die;
    };

    $transaction->set_data($data);

    return $transaction->save_and_close_or_die();
}

*_validate_domains_list = *Cpanel::Domain::Authz::validate_user_control_of_domains;

1;
