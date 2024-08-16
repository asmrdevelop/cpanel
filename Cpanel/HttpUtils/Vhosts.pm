package Cpanel::HttpUtils::Vhosts;

# cpanel - Cpanel/HttpUtils/Vhosts.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Context ();

sub update_vhost {
    require Carp;
    die Carp::longmess("Due to a race condition update_vhost_inside_transaction() must be used instead");
}

sub update_non_ssl_vhost_inside_transaction {
    my ( $httpd_conf_transaction, $domain_ref, $vhost_entry ) = @_;

    return _update_vhost_inside_transaction( $httpd_conf_transaction, $domain_ref, $vhost_entry, 'std' );
}

sub update_ssl_vhost_inside_transaction {
    my ( $httpd_conf_transaction, $domain_ref, $vhost_entry ) = @_;

    return _update_vhost_inside_transaction( $httpd_conf_transaction, $domain_ref, $vhost_entry, 'ssl' );
}

sub _update_vhost_inside_transaction {
    my ( $httpd_conf_transaction, $domain_ref, $vhost_entry, $std_or_ssl ) = @_;

    Cpanel::Context::must_be_list();

    $domain_ref = [ { 'domain' => $domain_ref, 'vhost_entry' => $vhost_entry } ] if !ref $domain_ref;

    my @ADD;
    my %REPLACE;

    foreach my $entry ( @{$domain_ref} ) {
        my $domain       = $entry->{'domain'};
        my $vhost_string = $entry->{'vhost_entry'};

        my $has_server_type = $httpd_conf_transaction->servername_type_is_active( $domain, $std_or_ssl );

        if ($has_server_type) {
            $REPLACE{$domain}{$std_or_ssl} = $vhost_string;
        }
        else {
            push @ADD, $vhost_string;
        }
    }

    my @entries = @ADD;

    my ( $ok, $msg ) = _do_transaction_work_for_update_vhost( \@entries, \@ADD, \%REPLACE, $httpd_conf_transaction );

    # Suppress uninitialized value warnings in consumers of this
    $msg ||= "";

    return wantarray ? ( $ok, $msg, \@entries ) : $ok;
}

sub _do_transaction_work_for_update_vhost {
    my ( $entries_ar, $arr_ar, $replace_hr, $httpd_conf_transaction ) = @_;

    for my $entry (@$arr_ar) {
        my ( $ok, $msg ) = $httpd_conf_transaction->add_vhost($entry);
        return ( 0, $msg ) if !$ok;
    }

    while ( my ( $domain, $entries ) = each %$replace_hr ) {
        for my $entry ( values %$entries ) {
            my ( $ok, $msg ) = $httpd_conf_transaction->replace_vhosts_by_name( $domain, $entry );
            return ( 0, $msg ) if !$ok;

            push @$entries_ar, $entry;
        }
    }

    return 1;
}

1;
