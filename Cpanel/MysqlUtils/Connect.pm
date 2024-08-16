package Cpanel::MysqlUtils::Connect;

# cpanel - Cpanel/MysqlUtils/Connect.pm              Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# Use this when you want to default to the root-default MySQL
# connection parameters.
#
# NOTE: The $dbi global here could be a source of frustration.
#----------------------------------------------------------------------

use strict;
use base 'Cpanel::MysqlUtils::Base';
use Cpanel::LoadModule               ();
use Cpanel::Compat::DBDmysql         ();
use Cpanel::DBI::Mysql               ();
use Cpanel::Exception                ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::IP::Loopback             ();

our $_TEST_DBSERVER;    # for tests only

our $dbh_singleton;
my $connected_db;

#Named args:
#   dbpass      (default: root's stored MySQL password)
#   dbserver    (default: root's stored MySQL server)
#       To use a filesystem socket instead, pass in "mysql_socket=$path_to_socket".
#   dbuser      (default: 'root')
#   database    (default: 'mysql')
#   extra_args  (default: none)
#       A hashref of additional arguments that need to be passed when creating
#       the DBI handle.
#
#NOTE: This works independently of the $dbh_singleton global.
#
sub new {
    my $class = shift;

    my (%OPTS) = @_;

    my $dbh_obj = get_dbi_handle(%OPTS);

    my $self = { 'dbh' => $dbh_obj, 'pid' => $$ };

    return bless $self, $class;
}

#This may be called either statically or dynamically, e.g.:
#   sqlcmd( $cmd_string, $opts_hr )
#   $obj->sqlcmd( $cmd_string, $opts_hr )
#
sub sqlcmd {
    my $self = _get_or_create_self( \@_ );

    my ( $cmds, $opts ) = @_;

    if ( !$opts->{'nodb'} ) {
        my $cmd_db = ( $opts->{'db'} || 'mysql' );
        if ( !$connected_db || $cmd_db ne $connected_db ) {
            if ( $self->_single_sql_cmd( 'use ' . $cmd_db . ';', $opts ) eq '0E0' ) {
                $connected_db = $cmd_db;
            }
        }
    }

    if ( ref $cmds ) {
        if ( !grep { m/^\s*(?:show|select)/i } @{$cmds} ) {
            return $self->_single_sql_cmd( join( ';', map { s/\s*;\s*$//g; $_ } @{$cmds} ) . ';', $opts );
        }
        else {
            my $results = '';
            my $last_result;
            foreach my $cmd ( @{$cmds} ) {
                my $result = $self->_single_sql_cmd( $cmd, $opts );
                if ( $cmd =~ /^\s*(?:show|select)/i ) {
                    $results .= $result;
                }
                elsif ( $result ne '0E0' ) {
                    $results .= $result;
                }
                else {
                    $last_result = $result;
                }
            }
            return $results || $last_result;
        }
    }
    else {
        return $self->_single_sql_cmd( $cmds, $opts );
    }
}

#This can be called either statically or dynamically.
#Its return is an array of hashrefs.
sub fetch_hashref {
    my $self = _get_or_create_self( \@_ );

    my ( $stmt, @bind ) = @_;

    my $sth = $self->{'dbh'}->prepare($stmt);

    if ( $sth->execute(@bind) ) {
        return $sth->fetchall_arrayref( {} );
    }

    return [];
}

=head1 get_dbi_handle()

Returns a DBI database handle as would be created by new.  This function takes
exactly the same arguments as new, except that it does not take a class as the
first argument.

This function is the preferred way to get a plain DBI handle for use with MySQL,
as it results in consistent handling of the socket location.

=cut

sub get_dbi_handle {
    my (%OPTS) = @_;

    my $dbuser   = $OPTS{'dbuser'} || Cpanel::MysqlUtils::MyCnf::Basic::getmydbuser('root') || 'root';
    my $dbpass   = $OPTS{'dbpass'} || Cpanel::MysqlUtils::MyCnf::Basic::getmydbpass('root') || '';
    my $dbserver = $_TEST_DBSERVER || $OPTS{'dbserver'}                                     || Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root') || 'localhost';
    my $dbport   = $OPTS{'dbport'} || Cpanel::MysqlUtils::MyCnf::Basic::getmydbport('root') || 3306;

    my %socket_args;
    if ( Cpanel::IP::Loopback::is_loopback($dbserver) ) {
        my $socket = Cpanel::MysqlUtils::MyCnf::Basic::getmydbsocket('root');
        $socket_args{'mysql_socket'} = $socket if $socket;
    }

    my %extra_args = ( $OPTS{'extra_args'} ? %{ $OPTS{'extra_args'} } : () );

    my %opts_rewritten = (
        ( !$_TEST_DBSERVER ? ( Username => $dbuser ) : () ),
        ( !$_TEST_DBSERVER ? ( Password => $dbpass ) : () ),

        ( $dbserver =~ m{\Amysql_socket} ? split( m{=}, $dbserver, 2 ) : ( host => $dbserver ) ),

        mysql_multi_statements => 1,
        mysql_local_infile     => ( $OPTS{'mysql_local_infile'} || 0 ),
        mysql_auto_reconnect   => 1,
        port                   => $dbport,

        RaiseError => 1,
        PrintError => 1,

        # A fail-safe in case, e.g., the server has hit its NOFILE rlimit,
        # in which case it can’t accept() any new connections, which makes
        # the client (whose socket is already established) hang as it waits
        # for the server to send its initial handshake.
        mysql_connect_timeout => 60,
    );

    if ( !$OPTS{'no-database'} ) {
        $opts_rewritten{'database'} = $OPTS{'database'} || 'mysql';
    }

    %opts_rewritten = ( %opts_rewritten, %socket_args, %extra_args );

    my $dbh_obj = Cpanel::DBI::Mysql->connect( \%opts_rewritten );

    # Perlcc has a problem with this in the connect line
    $dbh_obj->{'AutoInactiveDestroy'} = 1;

    return $dbh_obj;
}

#----------------------------------------------------------------------
# Stuff in here is best considered DEPRECATED.

# This is designed to be called as one of:
#   Cpanel::MysqlUtils::Connect::connect()
#   Cpanel::MysqlUtils::Connect->connect()
#
# NOTE: This function's return value, unlike the DBI method of the same name,
# is NOT a DB handle, but a 0/1 to indicate failure/success.
#
# The actual DB handle goes into the $dbh singleton.
#
sub connect {
    my $self = shift;

    if ( ref $self ) {
        return $self->SUPER::connect(@_);
    }
    else {
        return __PACKAGE__->SUPER::connect(@_);
    }

}

#NOTE: This works on either the package singleton or an instance.
sub disconnect {
    my $self = shift;

    if ( ref $self ) {
        return $self->SUPER::disconnect(@_);
    }
    else {
        return __PACKAGE__->SUPER::disconnect(@_);
    }
}

sub get_singleton {
    return $dbh_singleton;
}

sub set_singleton {
    my $class = shift;

    if ( ref $class eq __PACKAGE__ || ( !ref($class) && $class && $class eq __PACKAGE__ ) ) {
        $dbh_singleton = shift;
    }
    else {
        $dbh_singleton = $class;
    }

    return;
}

# End of "best considered DEPRECATED"
#----------------------------------------------------------------------

sub _single_sql_cmd {
    my ( $self, $cmd, $opts ) = @_;
    if ( $cmd =~ /^\s*(?:show|select)/i ) {
        my @results;
        eval {
            local $SIG{'__WARN__'} = sub { };

            my $req = $self->{'dbh'}->prepare($cmd);
            $req->execute();
            my $ref = $req->fetchrow_arrayref();
            if ($ref) {
                if ( $opts && ref $opts && $opts->{'column_names'} ) {
                    push @results, join( "\t", @{ $req->{'NAME'} } );
                }
                push @results, join( "\t", map { encode_mysql_output($_) } @{$ref} );
                while ( $ref = $req->fetchrow_arrayref() ) {
                    push @results, join( "\t", map { encode_mysql_output($_) } @{$ref} );
                }
            }
        };

        if ( $@ && !$opts->{'quiet'} ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
            print STDERR Cpanel::Carp::safe_longmess( Cpanel::Exception::get_string($@) );
        }

        return join( "\n", @results ) if !$@;
    }
    else {
        my $result;
        return 0E0 if ( $connected_db && $cmd =~ /^\s*use\s*\Q$connected_db\E\s*;\s*$/ );
        eval {
            local $SIG{'__WARN__'} = sub { };
            $result = $self->{'dbh'}->do($cmd);
        };
        if ($@) {
            if ( my $error_message = $self->{'dbh'}->errstr() ) {
                my $error_code = $self->{'dbh'}->err();
                my ($line)     = $error_message =~ /(at\s+line\s+[0-9]+)$/;
                my $state      = $self->{'dbh'}->state();
                return "ERROR " . $error_code . " ($state) @{[ $line || '??' ]}: " . $error_message;
            }
            return $@;
        }
        return $result;
    }

    return;
}

#Pass in an array ref to the calling function's args list.
#
#The return is one of either:
#   the invocant (i.e., that which isa(__PACKAGE__))
#   undef
#
#NOTE: This function will shift() that array's first element
#if that first arg isa(__PACKAGE__).
#
sub _get_dynamic_invocant {
    my ($args_ar) = @_;

    if (@$args_ar) {
        my ($arg1) = @$args_ar;

        local $@;
        if ( eval { $arg1->isa(__PACKAGE__) } ) {
            shift @$args_ar;
            return $arg1;
        }
    }

    return undef;
}

sub _get_or_create_self {
    my ($args_ar) = @_;

    return _get_dynamic_invocant($args_ar) || bless( { 'dbh' => __PACKAGE__->get_singleton() }, __PACKAGE__ );
}

sub decode_mysql_output {    ## no critic qw(Subroutines::RequireArgUnpacking)
    return $_[0] if $_[0] !~ tr/\\//;
    my ($string) = @_;
    $string =~ s/(?<!\\)\\t/\t/g;    # Restore tabs
    $string =~ s/(?<!\\)\\n/\n/g;    # Restore newlines
    $string =~ s/(?<!\\)\\0/\0/g;    # Restore nulls
    $string =~ s/\\\\/\\/g;          # Restore backslashes
    return $string;
}

sub encode_mysql_output {    ## no critic qw(Subroutines::RequireArgUnpacking)
    return 'NULL' if !defined $_[0];
    return $_[0]  if $_[0] !~ tr/\n\t\0\\//;
    my ($string) = @_;
    $string =~ s/\\/\\\\/g;    # Escape backslashes
    $string =~ s/\0/\\0/g;     # Escape nulls
    $string =~ s/\n/\\n/g;     # Escape newlines
    $string =~ s/\t/\\t/g;     # Escape tabs
    return $string;
}

1;
