package Cpanel::Pkgacct::Components::DNSSEC;

# cpanel - Cpanel/Pkgacct/Components/DNSSEC.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::Autodie          ();
use Cpanel::Exception        ();
use Cpanel::FileUtils::Write ();
use Cpanel::NameServer::Conf ();
use Cpanel::NameServer::DNSSEC::Cache();

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::DNSSEC - A pkgacct component module to backup the user's DNSSEC keys

=head1 SYNOPSIS

    use Cpanel::Config::LoadCpConf;
    use Cpanel::Pkgacct;
    use Cpanel::Pkgacct::Components::DNSSEC;
    use Cpanel::Output::Formatted::Terminal;

    my $user = 'root';
    my $work_dir = '/root/';
    my $pkgacct = Cpanel::Pkgacct->new(
        'is_incremental'    => 1,
        'is_userbackup'     => 1,
        'is_backup'         => 1,
        'user'              => $user,
        'new_mysql_version' => 'default',
        'uid'               => ( ( Cpanel::PwCache::getpwnam( $user ) )[2] || 10 ),
        'suspended'         => 1,
        'work_dir'          => $work_dir,
        'dns_list'          => 1,
        'domains'           => [],
        'now'               => time(),
        'cpconf'            => scalar Cpanel::Config::LoadCpConf::loadcpconf(),
        'OPTS'              => { 'db_backup_type' => 'all' },
        'output_obj'        => Cpanel::Output::Formatted::Terminal->new(),
    );

    $pkgacct->build_pkgtree($work_dir);
    $pkgacct->perform_component("DNSSEC");

=head1 DESCRIPTION

This module implements a C<Cpanel::Pkgacct::Component> module. It is responsible for packaging the
DNSSEC key data for a given user.

=cut

=head2 perform()

The function that actually does the work of backing up a user's DNSSEC keys

B<Returns>: C<1>

=cut

sub perform {
    my ($self) = @_;

    my $ns_obj = Cpanel::NameServer::Conf->new();
    return 1 if $ns_obj->type() ne 'powerdns';

    my $username   = $self->get_user();
    my $work_dir   = $self->get_work_dir() . '/dnssec_keys';
    my $output_obj = $self->get_output_obj();
    Cpanel::Autodie::mkdir_if_not_exists($work_dir);

    my @domains = Cpanel::NameServer::DNSSEC::Cache::has_dnssec( @{ $self->get_domains() } );
    foreach my $domain (@domains) {

        local $@;

        # If one key is missing, we still want to get the rest of
        # them so we warn and skip to the next one
        my $keys = eval { $ns_obj->list_keys($domain); };
        if ($@) {
            $output_obj->warn( Cpanel::Exception::get_string($@) );
            next;
        }
        next if not scalar keys %$keys;

        Cpanel::Autodie::mkdir_if_not_exists("$work_dir/$domain");

        foreach my $key ( values %$keys ) {
            my $target_path = "$work_dir/$domain/$key->{'key_tag'}_$key->{'key_type'}.key";
            Cpanel::FileUtils::Write::overwrite( $target_path, $key->{privatekey} )
              if $key->{privatekey};
        }
    }

    return 1;
}

1;
