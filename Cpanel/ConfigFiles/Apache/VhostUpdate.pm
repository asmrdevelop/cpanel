package Cpanel::ConfigFiles::Apache::VhostUpdate;

# cpanel - Cpanel/ConfigFiles/Apache/VhostUpdate.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

######################################################################################################
#### This module is a modified version of EA3’s distiller’s code, it will be cleaned up via ZC-5317 ##
######################################################################################################

use strict;
use warnings;

use Cpanel::HttpUtils::Config::Apache  ();
use Cpanel::HttpUtils::Vhosts          ();
use Cpanel::ConfigFiles::Apache::vhost ();
use Cpanel::Debug                      ();

=encoding utf-8

=head1 NAME

Cpanel::ConfigFiles::Apache::VhostUpdate - Update apache virtual hosts.

=head1 SYNOPSIS

    use Cpanel::ConfigFiles::Apache::VhostUpdate;

    Cpanel::ConfigFiles::Apache::VhostUpdate::do_vhost($vhost_name, $vhost_owner);

=head1 DESCRIPTION

Update Apache vhosts from their respective userdata.

=cut

=head2 do_vhost($vhost_name, $vhost_owner)

Update an apache vhost from the userdata.  The
$vhost_name and $vhost_owner correspond to the
userdata file at:

/var/cpanel/userdata/$vhost_owner/$vhost_name

=cut

sub do_vhost {
    my ( $vhost_name, $vhost_owner ) = @_;

    # do we want this here or in every function ?
    return if !$vhost_name || $vhost_name =~ /\.\.|\//;    # or validatore/normalizer ??

    require Cpanel::Template;                              # PPI USE OK - preload these before locking httpd.conf
    require Cpanel::Template::Plugin::Apache;              # PPI USE OK - preload these before locking httpd.conf

    my $httpd_conf_transaction = eval { Cpanel::HttpUtils::Config::Apache->new() };
    return ( 0, $@ ) if !$httpd_conf_transaction;

    my ( $ok, $std_vhost, $ssl_vhost ) = Cpanel::ConfigFiles::Apache::vhost::get_servername_vhosts_inside_transaction( $httpd_conf_transaction, $vhost_name, $vhost_owner );
    if ( !$ok || !$std_vhost ) {
        my ( $close_ok, $close_msg ) = $httpd_conf_transaction->abort();
        return ( 0, $close_msg ) if !$close_ok;
        die 'No standard vhost!' if !$std_vhost;
        return ( 0, $std_vhost );
    }

    my ( $update_status,     $update_statusmsg,     $updated_vhosts ) = Cpanel::HttpUtils::Vhosts::update_non_ssl_vhost_inside_transaction( $httpd_conf_transaction, $vhost_name, $std_vhost );
    my ( $ssl_update_status, $ssl_update_statusmsg, $ssl_updated_vhosts );

    if ($ssl_vhost) {
        ( $ssl_update_status, $ssl_update_statusmsg, $ssl_updated_vhosts ) = Cpanel::HttpUtils::Vhosts::update_ssl_vhost_inside_transaction( $httpd_conf_transaction, $vhost_name, $ssl_vhost );
    }

    my ( $save_ok, $save_msg ) = $httpd_conf_transaction->save();

    if ( !$save_ok ) {
        my $ref = ref $httpd_conf_transaction;
        if ( ref $save_msg && ref $save_msg eq 'ARRAY' ) {
            Cpanel::Debug::log_warn("Failed to save on $ref instance: @$save_msg");
        }
        else {
            Cpanel::Debug::log_warn("Failed to save on $ref instance: $save_msg");
        }
        return ( 0, $save_msg );
    }

    my ( $close_ok, $close_msg ) = $httpd_conf_transaction->close();

    if ( !$close_ok ) {
        my $ref = ref $httpd_conf_transaction;
        if ( ref $close_msg && ref $close_msg eq 'ARRAY' ) {
            Cpanel::Debug::log_warn("Failed to close on $ref instance: @$close_msg");
        }
        else {
            Cpanel::Debug::log_warn("Failed to close on $ref instance: $close_msg");
        }
        return ( 0, $close_msg );
    }

    if ( !$update_status ) {

        # Even if the first update fails
        # we still try the ssl_vhost update.
        #
        # In order to preserve existing behavior:
        # The first update is more important.
        # so if it fails lets return the results
        # for that.
        return ( $update_status, $update_statusmsg, $updated_vhosts );
    }
    elsif ( $ssl_vhost && !$ssl_update_status ) {
        return ( $ssl_update_status, $ssl_update_statusmsg, $ssl_updated_vhosts );
    }

    return ( 1, 'Success', $updated_vhosts );
}
1;

__END__
