package Cpanel::BandwidthDB::Base;

# cpanel - Cpanel/BandwidthDB/Base.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This module’s internals get accessed from Cpanel::BandwidthDB::Upgrade.
# That module is not a subclass.
#----------------------------------------------------------------------

use strict;

use Cpanel::Context                 ();
use Cpanel::DBI::SQLite             ();
use Cpanel::BandwidthDB::Read::Tiny ();
use Cpanel::BandwidthDB::State      ();

use base qw(
  Cpanel::AttributeProvider
);

use Cpanel::BandwidthDB::Constants ();

sub new {
    my ( $class, $username ) = @_;

    my $self = $class->SUPER::new();

    $self->set_attr( 'username', $username );

    $self->{'_orig_pid'} = $$;

    $self->{'_dbh'} = $self->_create_dbh();

    return $self;
}

sub list_domains {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    my $domains_ar = $self->{'_dbh'}->selectcol_arrayref(
        'SELECT name FROM domains WHERE name != ? ORDER BY name',
        undef,
        $Cpanel::BandwidthDB::Constants::UNKNOWN_DOMAIN_NAME,
    );

    return @$domains_ar;
}

sub has_domain {
    my ( $self, $domain ) = @_;

    my $moniker = $self->_normalize_domain($domain);

    $self->{'_select_id_for_domain_statement'} ||= $self->{'_dbh'}->prepare('SELECT id FROM domains WHERE name = ?');
    $self->{'_select_id_for_domain_statement'}->execute($moniker);
    return $self->{'_select_id_for_domain_statement'}->rows() ? 1 : 0;
}

sub _get_id_for_moniker {
    my ( $self, $moniker ) = @_;

    $self->{'_select_id_for_domain_statement'} ||= $self->{'_dbh'}->prepare('SELECT id FROM domains WHERE name = ?');

    $self->{'_select_id_for_domain_statement'}->execute($moniker);

    my $domain_id = ( $self->{'_select_id_for_domain_statement'}->fetchrow_array() )[0];
    die "Unknown domain: “$moniker”" if !defined $domain_id;

    return $domain_id;
}

#for subclassing
sub _dbi_attrs { }

my %cached_dbh;

#Called as a class method from a test.
sub _clear_dbh_cache {
    %cached_dbh = ();
    return;
}

#This avoids potential issues (e.g., segfault) with global destruction.
END { _clear_dbh_cache() }

#for subclassing - overrides _dbi_attrs()
sub _create_dbh {
    my ($self) = @_;

    my %dbi_attrs = $self->_dbi_attrs();

    my @connect_args = (
        db => $self->_name_to_path( $self->get_attr('username') ),
        map { $_ => $dbi_attrs{$_} } sort keys %dbi_attrs
    );

    if ( $dbi_attrs{'sqlite_open_flags'} & DBD::SQLite::OPEN_READWRITE() ) {

        #Only cache read handles
        return Cpanel::DBI::SQLite->connect( {@connect_args} );
    }

    #We can reuse a DB handle as long as it’s the same PID and connect args.
    #For added robustness, we also cache based on the EUID.
    my $cache_key = "$$-$>-@connect_args";

    return $cached_dbh{$cache_key} ||= Cpanel::DBI::SQLite->connect( {@connect_args} );
}

#NOTE: Tests call this logic directly.
sub _name_to_path {
    my ( $self, $username ) = @_;

    return Cpanel::BandwidthDB::Read::Tiny::_name_to_path($username);
}

*_PROTOCOLS = *Cpanel::BandwidthDB::State::get_enabled_protocols;

sub _INTERVALS {
    return @Cpanel::BandwidthDB::Constants::INTERVALS;
}

sub _interval_table {
    my ( $self, $interval ) = @_;

    return "bandwidth_$interval";
}

my $_normalize_domain_re;

sub _normalize_domain {
    my ( $self, $domain ) = @_;

    return $self->{'_normalize_domains'}{$domain} if $self->{'_normalize_domains'}{$domain};

    $_normalize_domain_re ||= join '|', map { quotemeta } @Cpanel::BandwidthDB::Constants::WILDCARD_PREFIXES;

    $domain =~ s<\A(?:$_normalize_domain_re)\.><*.>o;

    return ( $self->{'_normalize_domains'}{$domain} = $domain );
}

sub _get_schema_version {
    my ($self) = @_;

    return ( $self->{'_dbh'}->selectrow_array('SELECT * FROM version') )[0];
}

1;
