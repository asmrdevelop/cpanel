package Cpanel::AdvConfig::dovecotSSL;

# cpanel - Cpanel/AdvConfig/dovecotSSL.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::AdvConfig         ();
use Cpanel::SSL::Defaults     ();
use Cpanel::CPAN::Hash::Merge ();
use Cpanel::Dovecot::Compat   ();

use Try::Tiny;

use base 'Cpanel::AdvConfig::dovecot::Includes';

our $VERSION = '2.0';

our @ssl_protocol_order = qw/SSLv2 SSLv3 TLSv1 TLSv1.1 TLSv1.2/;

my $conf = {};

my $soft_defaults = {
    'ssl_key_file'     => $Cpanel::ConfigFiles::DOVECOT_SSL_KEY,
    'ssl_cert_file'    => $Cpanel::ConfigFiles::DOVECOT_SSL_CRT,
    'ssl_min_protocol' => Cpanel::SSL::Defaults::default_ssl_min_protocol(),
    'ssl_cipher_list'  => Cpanel::SSL::Defaults::default_cipher_list(),
};

=encoding utf-8

=head1 NAME

Cpanel::AdvConfig::dovecotSSL

=head1 DESCRIPTION

This module is intended to be used to build the dovecot SSL configuration file.

It uses Cpanel::AdvConfig::dovecot::Includes as a base class to do most of the work.

To rebuild this template you would call the rebuild_conf() method.

=head1 METHODS

=head2 new()

Constructor.

Sends arguments to the parent class constructor.

See Cpanel::AdvConfig::dovecot::Includes::new()

=cut

sub new ($pack) {
    return $pack->SUPER::new(
        {
            service       => 'dovecotSSL',
            verify_checks => [ '\A\s*ssl_cert\s*=', '\A\s*ssl_key\s*=' ],
            conf_file     => $Cpanel::ConfigFiles::DOVECOT_SSL_CONF,
        }
    );
}

=head2 get_config()

Builds a hashref to be applied to the configuration template.

Arguments are passed in a hashref.

Returns a hashref of template values.

=over

=item * reload - Bool - ( Optional ) Reset the conf cache.

=back

=cut

sub get_config ( $self, $args_ref = undef ) {

    # There's caching going on all over the place, so reset every global
    if ( exists $args_ref->{'reload'} && $args_ref->{'reload'} ) {
        $conf = {};
    }

    if ( $conf->{'_initialized'} ) {
        return wantarray ? ( 1, $conf ) : $conf;
    }

    $conf = Cpanel::CPAN::Hash::Merge::merge( $conf, $soft_defaults );

    my $local_conf = Cpanel::AdvConfig::load_app_conf( $self->{service} );
    if ( $local_conf && ref $local_conf eq 'HASH' ) {    # Had local configuration
        $self->_initialize_ssl_min_protocol_from_ssl_protocols_if_needed($local_conf);    #left in place as a transitional feature
        $conf = Cpanel::CPAN::Hash::Merge::merge( $conf, $local_conf );
    }

    # get the main conf to see if any of our target values are set so we can migrate them to the new template.
    my $main_conf = Cpanel::AdvConfig::load_app_conf('dovecot');
    for my $d ( keys %$soft_defaults ) {
        next if !$main_conf->{$d};
        $conf->{$d} = $main_conf->{$d};
    }

    $conf->{'_target_conf_file'}  = $self->{conf_file};
    $conf->{'_target_conf_perms'} = 0640;
    $conf->{'_initialized'}       = 1;

    return wantarray ? ( 1, $conf ) : $conf;
}

# Tested directly
# ssl_protocols has been phased out, but this function has been retained as a transitional feature.
sub _initialize_ssl_min_protocol_from_ssl_protocols_if_needed ( $self, $conf ) {

    # If the system does not support it do nothing
    return if !Cpanel::Dovecot::Compat::has_ssl_min_protocol();

    # If its already set in the config do nothing
    return if $conf->{'ssl_min_protocol'};

    if ( !length $conf->{'ssl_protocols'} ) {
        $conf->{'ssl_min_protocol'} = Cpanel::SSL::Defaults::default_ssl_min_protocol();
        return;
    }

    my %unsupported_protocols = ( 'SSLv2' => 1 );
    my $min_protocol          = 'SSLv3';
    my %current_protocols     = map { $_ => 1 } ( length $conf->{ssl_protocols} ? split( /\s+/, $conf->{ssl_protocols} ) : () );

    my $seen_not = 0;
    for my $protocol ( @ssl_protocol_order, @ssl_protocol_order ) {    # We transverse twice in case the ! protocol is the last one
        if ( $current_protocols{"!$protocol"} ) {
            $seen_not = $protocol;
        }
        elsif ( $seen_not || $current_protocols{$protocol} ) {
            $conf->{'ssl_min_protocol'} = $unsupported_protocols{$protocol} ? $min_protocol : $protocol;
            return;
        }
    }

    $conf->{'ssl_min_protocol'} = Cpanel::SSL::Defaults::default_ssl_min_protocol();
    return;
}

# For testing
sub reset_cache {
    $conf = {};

    return;
}

1;
