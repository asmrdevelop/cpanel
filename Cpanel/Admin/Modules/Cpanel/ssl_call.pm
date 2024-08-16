#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/ssl_call.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::ssl_call;

use cPstrict;

use parent qw( Cpanel::Admin::Base );

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::ssl_call - An adminbin module that handles additional SSL tasks for a user

=head1 SYNOPSIS

    use Cpanel::AdminBin::Call ();

    Cpanel::AdminBin::Call::call( 'Cpanel', 'ssl_call', 'GET_CACHED_CABUNDLE_URL', $url );

=head1 DESCRIPTION

AdminBin modules are called by a user from user-space to perform privileged actions
for that user. This AdminBin module performs additional SSL actions for a user.

NOTE: Please put all new SSL related AdminBin functions in this module.

=cut

__PACKAGE__->run() if !caller;

# Override to add process_ssl_pending_queue as it does this as user
use constant _allowed_parents => (
    __PACKAGE__->SUPER::_allowed_parents(),
    '/usr/local/cpanel/bin/process_ssl_pending_queue',
);

sub _actions {
    return qw(
      START_POLLING
      STOP_POLLING
      GET_KEY_AND_CERTIFICATES
      GET_CACHED_CABUNDLE_URL
      GET_AUTOSSL_OVERRIDE
      GET_AUTOSSL_PROBLEMS
      GET_AUTOSSL_PROVIDER
      ADD_AUTOSSL_EXCLUDED_DOMAINS
      SET_AUTOSSL_EXCLUDED_DOMAINS
      REMOVE_AUTOSSL_EXCLUDED_DOMAINS
      IS_AUTOSSL_CHECK_IN_PROGRESS
      START_AUTOSSL_CHECK
      GET_SSL_VHOSTS
      FETCH_INSTALLED_KEY_BY_ECDSA_CURVE_AND_POINT
    );
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 FETCH_INSTALLED_KEY_BY_ECDSA_CURVE_AND_POINT( $CURVE_NAME, $POINT_HEX )

Returns the installed key for a given ECDSA curve name and public point
(hex, uncompressed).

This is an ECDSA analogue to C<FETCHBYMODULUS> in the older C<ssl>
admin binary.

=cut

sub FETCH_INSTALLED_KEY_BY_ECDSA_CURVE_AND_POINT ( $self, $curve_name, $point_hex ) {
    require Cpanel::Crypt::ECDSA::Validate;

    $self->whitelist_exceptions(
        ['Cpanel::Exception::InvalidParameter'],
        sub {

            # We *could* accept compressed public points, but for now
            # let’s require uncompressed.
            Cpanel::Crypt::ECDSA::Validate::validate_curve_name_and_point(
                $curve_name, $point_hex,
            );
        },
    );

    my $atls_idx = Cpanel::Apache::TLS::Index->new();

    my $username = $self->get_caller_username();

    my $key_pem;
    for my $rec ( $atls_idx->get_for_ecdsa_curve_and_point( $curve_name, $point_hex ) ) {

        # Don’t return the key for a vhost that the caller doesn’t own.
        if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $self->get_caller_username(), $rec->{'vhost_name'} ) ) {
            $key_pem = ( Cpanel::Apache::TLS->get_tls( $rec->{'vhost_name'} ) )[0];
            last;
        }
    }

    return $key_pem;
}

#This name works because Domain TLS is a subset of Apache TLS.
sub GET_KEY_AND_CERTIFICATES {
    my ( $self, $vhost ) = @_;

    $self->_authz();

    require Cpanel::Context;
    Cpanel::Context::must_be_list();

    require Cpanel::Config::userdata::Load;

    #verify user control of the vhost
    if ( !Cpanel::Config::userdata::Load::user_has_ssl_domain( $self->get_caller_username(), $vhost ) ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'InvalidParameter', 'You do not control an [asis,SSL] website named “[_1]”.', [$vhost] );
    }

    require Cpanel::Apache::TLS;
    return Cpanel::Apache::TLS->get_tls($vhost);
}

sub GET_CACHED_CABUNDLE_URL {
    my ( $self, $url ) = @_;

    require URI::Split;
    my ( $scheme, $auth, $path ) = URI::Split::uri_split($url);

    if ( grep { !$_ } $scheme, $auth, $path ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,URL].', [$url] );
    }

    require Cpanel::SSL::CABundleCache;
    return Cpanel::SSL::CABundleCache->load($url);
}

sub START_POLLING {
    my ($self) = @_;

    $self->_authz();

    require Cpanel::SSL::PendingQueue::Cron;
    Cpanel::SSL::PendingQueue::Cron::add_polling_cron_entry_for_user_if_needed( $self->get_caller_username() );

    return;
}

sub STOP_POLLING {
    my ($self) = @_;

    $self->_authz();

    require Cpanel::SSL::PendingQueue::Cron;
    Cpanel::SSL::PendingQueue::Cron::remove_polling_cron_entry_for_user_if_exists( $self->get_caller_username() );

    return;
}

=head2 GET_AUTOSSL_PROBLEMS()

Returns the result of L<Cpanel::SSL::Auto::Problems>’s
C<get_for_user()> method for the calling user, with the C<log>
stripped out of each item since it’s not relevant to a cPanel user.

=cut

sub GET_AUTOSSL_PROBLEMS {
    my ($self) = @_;

    $self->_authz();

    require Cpanel::SSL::Auto::Problems;
    my $probs_ar = Cpanel::SSL::Auto::Problems->new()->get_for_user( $self->get_caller_username() );

    delete $_->{'log'} for @$probs_ar;

    return $probs_ar;
}

=head2 START_AUTOSSL_CHECK()

Start an AutoSSL check for the user.

=cut

sub START_AUTOSSL_CHECK {
    my ($self) = @_;

    $self->_authz();

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task( ['SSLTasks'], "autossl_check " . $self->get_caller_username() );

    return 1;
}

=head2 IS_AUTOSSL_CHECK_IN_PROGRESS()

Returns 1 or 0 if autossl_check is in progress for the current
user

=cut

sub IS_AUTOSSL_CHECK_IN_PROGRESS {
    my ($self) = @_;

    require Cpanel::SSL::Auto::Log;

    my $caller_username = $self->get_caller_username();

    my @entries = sort { $b->{'start_time'} cmp $a->{'start_time'} } Cpanel::SSL::Auto::Log->get_catalog();

    foreach my $log_ref (@entries) {
        if ( $log_ref->{'username'} eq $caller_username || $log_ref->{'username'} eq '*' ) {
            return $log_ref->{'in_progress'} ? 1 : 0;
        }
    }

    return 0;
}

sub GET_AUTOSSL_OVERRIDE {
    my ($self) = @_;

    $self->_authz();

    require Cpanel::SSL::Auto::Config::Read;
    my $conf     = Cpanel::SSL::Auto::Config::Read->new();
    my $metadata = $conf->get_metadata();

    return $metadata->{'clobber_externally_signed'} || 0;
}

sub GET_AUTOSSL_PROVIDER {
    my ($self) = @_;

    $self->_authz();

    require Cpanel::SSL::Auto::Config::Read;
    my $conf = Cpanel::SSL::Auto::Config::Read->new();

    return $conf->get_provider();
}

=head2 ADD_AUTOSSL_EXCLUDED_DOMAINS

This function adds new AutoSSL excluded domains to a user's excluded config file. An excluded domain is one that
AutoSSL does not maintain the SSL certificates for.

=head3 Input

=over 3

=item C<ARRAYREF> domains

    An arrayref of domains to add to the excluded list for the user.

=back

=head3 Output

=over 3

=item C<NONE> None

=back

=head3 Exceptions

=over 3

=item This can throw any exception Cpanel::SSL::Auto::Exclude::Set::add_user_excluded_domains can throw.

=back

=cut

sub ADD_AUTOSSL_EXCLUDED_DOMAINS {
    my ( $self, $domains ) = @_;

    $self->_authz();

    require Cpanel::SSL::Auto::Exclude::Set;
    Cpanel::SSL::Auto::Exclude::Set::add_user_excluded_domains(
        'user'    => $self->get_caller_username(),
        'domains' => $domains
    );

    return;
}

=head2 SET_AUTOSSL_EXCLUDED_DOMAINS

This function sets the AutoSSL excluded domains to a user's excluded config file. An excluded domain is one that
AutoSSL does not maintain the SSL certificates for.

=head3 Input

=over 3

=item C<ARRAYREF> domains

    An arrayref of domains to set to the excluded list for the user.

=back

=head3 Output

=over 3

=item C<NONE> None

=back

=head3 Exceptions

=over 3

=item This can throw any exception Cpanel::SSL::Auto::Exclude::Set::set_user_excluded_domains can throw.

=back

=cut

sub SET_AUTOSSL_EXCLUDED_DOMAINS {
    my ( $self, $domains ) = @_;

    $self->_authz();

    require Cpanel::SSL::Auto::Exclude::Set;
    Cpanel::SSL::Auto::Exclude::Set::set_user_excluded_domains(
        'user'    => $self->get_caller_username(),
        'domains' => $domains
    );

    return;
}

=head2 REMOVE_AUTOSSL_EXCLUDED_DOMAINS

This function removes the AutoSSL excluded domains from a user's excluded config file. An excluded domain is one that
AutoSSL does not maintain the SSL certificates for.

=head3 Input

=over 3

=item C<ARRAYREF> domains

    An arrayref of domains to remove from the excluded list for the user.

=back

=head3 Output

=over 3

=item C<NONE> None

=back

=head3 Exceptions

=over 3

=item This can throw any exception Cpanel::SSL::Auto::Exclude::Set::remove_user_excluded_domains can throw.

=back

=cut

sub REMOVE_AUTOSSL_EXCLUDED_DOMAINS {
    my ( $self, $domains ) = @_;

    $self->_authz();

    require Cpanel::SSL::Auto::Exclude::Set;
    Cpanel::SSL::Auto::Exclude::Set::remove_user_excluded_domains(
        'user'    => $self->get_caller_username(),
        'domains' => $domains
    );

    return;
}

sub _authz {
    my ($self) = @_;

    require Cpanel::Security::Authz;
    Cpanel::Security::Authz::verify_user_has_feature(
        $self->get_caller_username(),
        'sslinstall',
    );
    return;
}

=head2 GET_SSL_VHOSTS()

Returns a hash of the user's vhosts (and aliases!) with currently working and installed SSL.

Example output:
    (
        'nugs.test' => {
            'ssl_valid' => 1,
            'alias_ssl_valid' => {
                'mail.nugs.test' => 1,
                'www.nugs.test' => 1
            },
            'all_aliases_valid' => 1
         },
        'addonsub.nugs.test' => {
            'ssl_valid' => 0,
            'all_aliases_valid' => '',
            'alias_ssl_valid' => {
                'www.addonsub.nugs.test' => 0,
                'mail.addon.test' => 0,
                'www.addon.test' => 0,
                'addon.test' => 0
            }
        },
    )

It's wise to cache the result; you may end up reading the same cert repeatedly otherwise.

=cut

sub GET_SSL_VHOSTS {
    my ( $self, $vhost_cache ) = @_;

    #
    # You'd think that the vhost_is_ssl flag in Cpanel::WebVhosts::list_domains would be enough.
    # The problem with that line of thinking is that this only checks whether SSL is *installed*.
    # We still gotta do extended validation on the installed certificate.
    #
    require Cpanel::WebVhosts;
    require Cpanel::ArrayFunc::Uniq;
    require Cpanel::SSL::Objects::Certificate;
    require Cpanel::Apache::TLS::Index;

    my $user = $self->get_caller_username();

    # This is the *only* reason this is in an adminbin. The index is owned by root.
    my $TLSIndex = Cpanel::Apache::TLS::Index->new();

    #Note here we are returning the list of *aliases* as well (the domain param).
    #This will prove useful in the event you wish to have information as to whether ALL aliases are in a SAN on your certs
    my @real_domains = ref $vhost_cache eq 'ARRAY' ? @$vhost_cache : Cpanel::WebVhosts::list_domains($user);
    my @vhosts       = Cpanel::ArrayFunc::Uniq::uniq( map { $_->{vhost_name} } @real_domains );
    my %alias_map    = map { $_->{domain} => $_ } @real_domains;
    my %vhost_hash;

    #Optimized™
    $TLSIndex->{vhost_cache} = $TLSIndex->get_for_vhosts(@vhosts);

    foreach my $vh (@vhosts) {
        $vhost_hash{$vh}{ssl_valid} = _ssl_actually_valid( $TLSIndex, $alias_map{$vh} );
        my @aliases = map { $_->{domain} } grep { $_->{vhost_name} eq $vh && $_->{domain} ne $vh } @real_domains;
        foreach my $alias (@aliases) {
            $vhost_hash{$vh}{alias_ssl_valid}{$alias} = _ssl_actually_valid( $TLSIndex, $alias_map{$alias} );
        }

        #Convenience™
        $vhost_hash{$vh}{all_aliases_valid} = !grep { !$_ } values( %{ $vhost_hash{$vh}{alias_ssl_valid} } );
    }

    return %vhost_hash;
}

sub _ssl_actually_valid {
    my ( $TLSIndex, $dom_obj ) = @_;

    #Unfortunately you *CAN* have an SSL cert without the san for things like www.
    #As such we *must* check the cert from the parent vhost to see if it's in the SAN list.
    my $domain = $dom_obj->{vhost_name};
    my $alias  = $dom_obj->{domain};

    #Prevent uninit warnings in eq
    $TLSIndex->{vhost_cache}{$domain}{issuer}  //= '';
    $TLSIndex->{vhost_cache}{$domain}{subject} //= '';

    #Mangle data due to schema mismatch
    $TLSIndex->{vhost_cache}{$domain}{domains}        = $TLSIndex->{vhost_cache}{$domain}{certificate_domains};
    $TLSIndex->{vhost_cache}{$domain}{is_self_signed} = $TLSIndex->{vhost_cache}{$domain}{issuer} eq $TLSIndex->{vhost_cache}{$domain}{subject};

    #Eject clearly bogus stuff
    return 0 if !$TLSIndex->{vhost_cache}{$domain}{subject};

    my $cert = Cpanel::SSL::Objects::Certificate->new_from_parsed_and_text( $TLSIndex->{vhost_cache}{$domain}, '' );    # Optimized™
    return 0 unless $cert && ref $cert->parsed() eq 'HASH';

    return 0 unless $cert->valid_for_domain($alias) == 1;
    return 0 if $cert->is_self_signed();
    my $time = time();
    require Cpanel::Time::ISO;
    return 0 if $time < Cpanel::Time::ISO::iso2unix( $cert->not_before() );
    return 0 if $time > Cpanel::Time::ISO::iso2unix( $cert->not_after() );
    return 1;
}

1;
