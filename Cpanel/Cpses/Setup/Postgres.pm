package Cpanel::Cpses::Setup::Postgres;

# cpanel - Cpanel/Cpses/Setup/Postgres.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Cpses::Postgres::Config ();

our $cpses_postgres_ip = $Cpanel::Cpses::Postgres::Config::POSTGRES_CONFIGURED_PAM_IP;

use Cpanel::PwCache::Group         ();
use Cpanel::PostgresUtils          ();
use Cpanel::PostgresUtils::PgPass  ();
use Cpanel::Transaction::File::Raw ();
use Cpanel::StringFunc::Trim       ();
use Cpanel::PostgresAdmin::Check   ();
use Cpanel::SysAccounts            ();

sub new {
    my ($class) = @_;

    my $self = {};
    bless $self, $class;

    $self->{'has_postgres'} = Cpanel::PostgresAdmin::Check::is_configured()->{'status'};

    return $self if !$self->{'has_postgres'};

    my $pgsql_user = Cpanel::PostgresUtils::PgPass::getpostgresuser();
    die "could not determine postgres user" if !$pgsql_user;

    my $pgsql_data = Cpanel::PostgresUtils::find_pgsql_data();
    die "pgsql data directory not found" if !$pgsql_data;

    my $pgsql_version = Cpanel::PostgresUtils::get_version();
    die "could not determine postgres version" if !$pgsql_version;

    $self->{'pgsql_user'}    = $pgsql_user;
    $self->{'pgsql_data'}    = $pgsql_data;
    $self->{'pgsql_version'} = $pgsql_version;

    return $self;
}

sub activate {
    my ($self) = @_;

    if ( !$self->{'has_postgres'} ) { return 1; }

    $self->ensure_groups();

    $self->ensure_conf_listens_for_cpses();

    $self->ensure_conf_auths_for_cpses();

    if ( $self->{'pgsql_restart_needed'} ) {
        require Cpanel::Services::Restart;
        Cpanel::Services::Restart::restartservice('postgresql');
    }

    return 1;
}

sub ensure_groups {
    my ($self) = @_;

    my $pgsql_user   = $self->{'pgsql_user'};
    my @users_groups = Cpanel::PwCache::Group::getgroups($pgsql_user);

    return 1 if grep { $_ eq 'cpses' } @users_groups;

    return Cpanel::SysAccounts::add_user_to_group( 'cpses', $pgsql_user );
}

sub ensure_conf_listens_for_cpses {
    my ($self) = @_;
    my $pgsql_data = $self->{'pgsql_data'};

    my $trans_obj = eval { Cpanel::Transaction::File::Raw->new( path => "$pgsql_data/postgresql.conf", ownership => [ $self->{'pgsql_user'} ] ); };
    return ( 0, $@ ) if !$trans_obj;

    my $postgres_conf_txt_ref = $trans_obj->get_data();

    if (   ${$postgres_conf_txt_ref} =~ m/^[ \t]*listen_addresses.*?\Q$cpses_postgres_ip\E/mg
        || ${$postgres_conf_txt_ref} =~ m/^[ \t]*listen_addresses.*?\*/mg )    # wildcard ok
    {
        my ( $ok, $err ) = $trans_obj->close();
        return ( 0, $err ) if !$ok;

        return ( 1, "Conf already setup" );
    }

    my @conf = split( /\n/, ${$postgres_conf_txt_ref} );
    my $added_line;
    my $line_count = $#conf;
    foreach my $find_directive (
        qr/^[ \t]*listen_addresses/,
        qr/^[ \t]*#[ \t]*listen_addresses/i
    ) {
        for ( my $line = 0; $line <= $line_count; $line++ ) {
            my $line_text = $conf[$line];
            if ( $line_text =~ $find_directive ) {
                my ( $directive, $separator, $listen_addresses ) =
                  split( /([\t ]*=[\t ]*)/, $line_text );

                my ($end_of_line_comment) = $listen_addresses =~ m/(#.*?)$/;

                $directive =~ s/^[ \t]*#//;    # uncomment if needed

                $listen_addresses =~ s/(#.*?)$//;    # remove end of line comments
                $listen_addresses = Cpanel::StringFunc::Trim::ws_trim($listen_addresses);
                $listen_addresses =~ s/^["']+//;     #remove quotes
                $listen_addresses =~ s/["']+$//;     #remove quotes

                my %addresses = map { $_ => undef } split( m/[\t ]*,[\t ]*/, $listen_addresses );
                $addresses{$cpses_postgres_ip} = 1 unless exists $addresses{'*'};

                $conf[$line] = $directive . $separator . q{'} . join( ', ', sort keys %addresses ) . q{'} . ' ' . ( $end_of_line_comment || '' );
                $added_line = 1;
                last;
            }
        }
    }

    if ( !$added_line ) {
        push @conf, qq{listen_addresses = 'localhost, $cpses_postgres_ip'};
    }

    ${$postgres_conf_txt_ref} = join( "\n", @conf );

    my ( $save_ok, $save_status ) = $trans_obj->save_and_close();
    return ( 0, "Failed to modify conf: $save_status" ) if !$save_ok;

    $self->{'pgsql_restart_needed'} = 1;
    return ( 1, "Conf setup" );
}

sub ensure_conf_auths_for_cpses {
    my ($self) = @_;
    my $pgsql_data = $self->{'pgsql_data'};

    my $trans_obj = eval { Cpanel::Transaction::File::Raw->new( path => "$pgsql_data/pg_hba.conf", ownership => [ $self->{'pgsql_user'} ] ); };

    my $pghba_conf_txt_ref = $trans_obj->get_data();

    return ( 0, $@ ) if !$trans_obj;

    my $pam_cfg = ( $self->{'pgsql_version'} >= 8.4 ? 'pamservice=' : '' ) . "postgresql_cpses";

    if ( ${$pghba_conf_txt_ref} =~ m/^[ \t]*host\s+samerole.*?\Q$cpses_postgres_ip\E.*?\Q$pam_cfg\E/mg ) {
        my ( $ok, $err ) = $trans_obj->close();
        return ( 0, $err ) if !$ok;

        return ( 1, "Conf already setup" );
    }

    my $line_to_add = "host samerole all $cpses_postgres_ip 255.255.255.255 pam $pam_cfg";

    my @conf = grep ( !m/ \Q$cpses_postgres_ip\E /, split( /\n/, ${$pghba_conf_txt_ref} ) );
    my $added_line;
    my $line_count = $#conf;
    for ( my $line = 0; $line <= $line_count; $line++ ) {
        my $line_text = $conf[$line];
        if ( !$added_line && $line_text !~ m/^\s*#/ && $line_text !~ m/^\s*$/ ) {
            splice( @conf, $line, 0, $line_to_add );
            $added_line = 1;
        }
        elsif ( $line_text !~ m/^\s*#/ && $line_text =~ m/\Q$cpses_postgres_ip\E/ ) {

            # remove lines referencing 127.0.0.200 without samerole
            splice( @conf, $line, 1 );
        }
    }

    if ( !$added_line ) {
        push @conf, $line_to_add;
    }

    ${$pghba_conf_txt_ref} = join( "\n", @conf );

    my ( $save_ok, $save_status ) = $trans_obj->save_and_close();
    return ( 0, "Failed to modify conf: $save_status" ) if !$save_ok;

    $self->{'pgsql_restart_needed'} = 1;
    return ( 1, "Conf setup" );
}

1;
