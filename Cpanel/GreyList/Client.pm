package Cpanel::GreyList::Client;

# cpanel - Cpanel/GreyList/Client.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::GreyList::Config  ();
use Cpanel::GreyList::Handler ();

use Cpanel::Logger ();

sub new {
    my ($class) = @_;
    my $self = {
        'disabled' => ( Cpanel::GreyList::Config::is_enabled() ? 0 : 1 ),
        'logger'   => Cpanel::Logger->new( { 'alternate_logfile' => Cpanel::GreyList::Config::get_logfile_path() } ),
    };
    return bless $self, $class;
}

sub get_deferred_list {
    my ( $self, $opts ) = @_;
    return if $self->{'disabled'};
    $opts ||= {};

    _fix_limit_sort_opts($opts);

    my $handler = Cpanel::GreyList::Handler->new();
    my $result  = $handler->get_deferred_list( $self->{'logger'}, [ $opts->{'limit'}, $opts->{'offset'}, $opts->{'order_by'}, $opts->{'order'}, $opts->{'is_filter'}, $opts->{'filter'} ], 'send_raw_response' );
    return $result;
}

sub create_trusted_host {
    my ( $self, $ip, $comment ) = @_;
    return if $self->{'disabled'};
    return if !$ip;

    my $handler = Cpanel::GreyList::Handler->new();
    my $result  = $handler->create_trusted_host( $self->{'logger'}, [ $ip, $comment ], 'send_raw_response' );
    return $result;
}

sub read_trusted_hosts {
    my $self = shift;
    return if $self->{'disabled'};

    my $handler = Cpanel::GreyList::Handler->new();
    my $result  = $handler->read_trusted_hosts( $self->{'logger'}, 'send_raw_response' );
    return $result;
}

sub delete_trusted_host {
    my ( $self, $ip ) = @_;
    return if $self->{'disabled'};
    return if !$ip;

    my $handler = Cpanel::GreyList::Handler->new();
    my $result  = $handler->delete_trusted_host( $self->{'logger'}, [$ip] );
    return $result;
}

sub verify_trusted_hosts {
    my ( $self, $hosts_hr ) = @_;
    return if $self->{'disabled'};
    return if !$hosts_hr || 'HASH' ne ref $hosts_hr || !scalar keys %{$hosts_hr};

    my $handler = Cpanel::GreyList::Handler->new();
    my $result  = $handler->verify_trusted_hosts( $self->{'logger'}, $hosts_hr, 'send_raw_response' );
    return $result;
}

sub is_greylisting_enabled {
    my ( $self, $domain ) = @_;
    return if $self->{'disabled'};
    return if !$domain;

    return Cpanel::GreyList::Handler->new->is_greylisting_enabled($domain);
}

sub disable_opt_out_for_domains {
    my ( $self, $domains_ar ) = @_;
    return if $self->{'disabled'};
    return if not( 'ARRAY' eq ref $domains_ar && scalar @{$domains_ar} );

    return Cpanel::GreyList::Handler->new->disable_opt_out_for_domains($domains_ar);
}

sub enable_opt_out_for_domains {
    my ( $self, $domains_ar ) = @_;
    return if $self->{'disabled'};
    return if not( 'ARRAY' eq ref $domains_ar && scalar @{$domains_ar} );

    return Cpanel::GreyList::Handler->new->enable_opt_out_for_domains($domains_ar);
}

sub add_entries_for_common_mail_provider {
    my ( $self, $provider, $ips_ar ) = @_;
    return if $self->{'disabled'};
    return if not length $provider;
    return if not 'ARRAY' eq ref $ips_ar && scalar @{$ips_ar};

    return Cpanel::GreyList::Handler->new->add_entries_for_common_mail_provider( $self->{'logger'}, [ $provider, $ips_ar ] );
}

sub delete_entries_for_common_mail_provider {
    my ( $self, $provider ) = @_;
    return if $self->{'disabled'};
    return if not length $provider;

    return Cpanel::GreyList::Handler->new->delete_entries_for_common_mail_provider( $self->{'logger'}, [$provider] );
}

sub trust_entries_for_common_mail_provider {
    my ( $self, $provider ) = @_;
    return if $self->{'disabled'};
    return if not length $provider;

    return Cpanel::GreyList::Handler->new->trust_entries_for_common_mail_provider($provider);
}

sub untrust_entries_for_common_mail_provider {
    my ( $self, $provider ) = @_;
    return if $self->{'disabled'};
    return if not length $provider;

    return Cpanel::GreyList::Handler->new->untrust_entries_for_common_mail_provider($provider);
}

sub list_entries_for_common_mail_provider {
    my ( $self, $provider ) = @_;
    return if $self->{'disabled'};
    return if not length $provider;

    return Cpanel::GreyList::Handler->new->list_entries_for_common_mail_provider($provider);
}

sub get_common_mail_providers {
    my $self = shift;
    return if $self->{'disabled'};
    return Cpanel::GreyList::Handler->new->get_common_mail_providers();
}

sub add_mail_provider {
    my ( $self, $provider, $display_name, $last_updated ) = @_;
    return if $self->{'disabled'};
    return if not( length $provider && length $display_name );

    return Cpanel::GreyList::Handler->new->add_mail_provider( $provider, $display_name, $last_updated );
}

sub remove_mail_provider {
    my ( $self, $provider ) = @_;
    return if $self->{'disabled'};
    return if not length $provider;

    return Cpanel::GreyList::Handler->new->remove_mail_provider($provider);
}

sub rename_mail_provider {
    my ( $self, $old_provider, $new_provider ) = @_;
    return if $self->{'disabled'};
    return unless length $old_provider && length $new_provider;

    return Cpanel::GreyList::Handler->new->rename_mail_provider( $old_provider, $new_provider );
}

sub bump_last_updated_for_mail_provider {
    my ( $self, $provider, $last_updated ) = @_;
    return if $self->{'disabled'};
    return if not length $provider;

    return Cpanel::GreyList::Handler->new->bump_last_updated_for_mail_provider( $provider, $last_updated );
}

sub update_display_name_for_mail_provider {
    my ( $self, $provider, $display_name ) = @_;
    return if $self->{'disabled'};
    return unless length $provider && length $display_name;

    return Cpanel::GreyList::Handler->new->update_display_name_for_mail_provider( $provider, $display_name );
}

sub _fix_limit_sort_opts {
    my $opts = shift;
    $opts->{'limit'}     //= 20;
    $opts->{'offset'}    //= 0;
    $opts->{'order_by'}  //= 'id';
    $opts->{'order'}     //= 'ASC';
    $opts->{'is_filter'} //= 0;
    $opts->{'filter'}    //= '';

    return 1;
}

1;
