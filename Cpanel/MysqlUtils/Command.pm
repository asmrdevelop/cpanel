package Cpanel::MysqlUtils::Command;

# cpanel - Cpanel/MysqlUtils/Command.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule               ();
use Cpanel::DbUtils                  ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::MysqlUtils::Quote        ();

my $mysql_bin;
my $mycnf;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Command

=head1 SYNOPSIS

    use Cpanel::MysqlUtils::Command ();
    my $zero_or_one_result = Cpanel::MysqlUtils::Command::db_exists($user_db);
    my $result = Cpanel::MysqlUtils::Command::sqlcmd( "SHOW DATABASES;");

=head1 DESCRIPTION

This module contains some utility features for acting on or checking the state of a database.

=head1 FUNCTIONS


=cut

=head2 sqlcmd( SCALAR|ARRAYREF, optional HASHREF )

This function sends SQL commands to the MySQL server through either the
Cpanel::MysqlUtils::Connect singleton or via the MySQL client binary.

=head3 Arguments

=over 4

=item CMD_OR_CMD_ARRAYREF    - SCALAR|ARRAYREF of SCALARS - This represents the command or
                              commands (if arrayref) to be sent to the MySQL server.

=item OPTIONS    - HASHREF - This is an optional hashref used to pass in options to the sqlcmd calls.

=back

=head3 Returns

A scalar value with the output of all the commands passed in.

=head3 Exceptions

Anything Cpanel::SafeRun::Object can throw.
Anything Cpanel::LoadModule::load_perl_module can throw.

=cut

sub sqlcmd {
    my (@args) = @_;

    my $module = _get_cpmysql_module();
    return _forked_sqlcmd(@args) if !$module;

    my $result = $module->instance()->sqlcmd(@args);

    if ( !length $result ) {
        $result = undef;
    }

    return $result;
}

=head2 get_db_handle()

This function gets a database handle from the Cpanel::MysqlUtils::Connect singleton, if it's loaded.

=head3 Arguments

=over 4

None.

=back

=head3 Returns

The database handle to the MySQL server.

=cut

sub get_db_handle {
    my $module = _get_cpmysql_module() or die "No cpmysql module!";
    return $module->instance()->db_handle();
}

=head2 db_exists( SCALAR )

This function checks whether a passed in database is in MySQL or not.

=head3 Arguments

=over 4

=item $db    - SCALAR - The name of the database to check the existence of.

=back

=head3 Returns

This function returns 1 if the database exists and 0 if the database does not exist.

=head3 Exceptions

Anything sqlcmd can throw.

=cut

sub db_exists {
    my ($db) = @_;
    $db = Cpanel::MysqlUtils::Quote::safesqlstring($db);
    my $ms = sqlcmd("SHOW DATABASES LIKE '$db';") || '';
    $ms =~ s/\s//g;

    return ( $ms =~ /\A\Q$db\E\z/ ) ? 1 : 0;
}

=head2 user_exists( SCALAR, DBI_HANDLE )

This function determines if a passed in user exists in MySQL.

=head3 Arguments

=over 4

=item $user    - SCALAR - The name of the user to check the existence of.

=item $dbh    - DBI_HANDLE - The optional handle to the MySQL database. If this isn't passed sqlcmd will be used.

=back

=head3 Returns

This function returns 1 if the user exists and 0 if the user does not exist in the MySQL database.

=head3 Exceptions

Anything sqlcmd or selectrow_array can throw.

=cut

sub user_exists {
    my ( $user, $dbh ) = @_;

    my $exists;
    if ($dbh) {
        $exists = $dbh->selectrow_array( "SELECT COUNT(user) FROM mysql.user WHERE user = ? LIMIT 1;", undef, $user );
    }
    else {
        my $quoted_user = Cpanel::MysqlUtils::Quote::quote($user);

        $exists = sqlcmd("SELECT COUNT(user) FROM mysql.user WHERE user = $quoted_user LIMIT 1;");
    }
    return $exists ? 1 : 0;
}

sub get_db_names {
    my $out = sqlcmd( "SHOW DATABASES", { nodb => 1 } );

    return [ split m{[\r\n]+}, $out ];
}

sub _get_cpmysql_module {
    if ( exists $INC{'Cpanel/MysqlUtils/Connect.pm'} ) {
        return 'Cpanel::MysqlUtils::Connect';
    }

    return;
}

sub _forked_sqlcmd {
    my ( $cmds, $opts ) = @_;

    #
    # no opts defaults to mysql db
    #
    my ( @preargs, @args );
    if ( $opts->{'nodb'} ) {
        $mycnf ||= Cpanel::MysqlUtils::MyCnf::Basic::get_dot_my_dot_cnf('root');
        @preargs = ( '--defaults-extra-file=' . $mycnf );
    }
    else {
        @args = ( $opts->{'db'} || 'mysql' );
    }
    push @preargs, '-N' unless $opts->{'column_names'};

    if ( $opts->{'multi_fallback_ok'} && ref $cmds ) {
        $cmds = join( ";\n", @{$cmds} );
    }

    my $result = '';
    my $retcode;
    my $did_select;
    foreach my $cmd ( ref $cmds ? ( @{$cmds} ) : ($cmds) ) {
        $mysql_bin ||= Cpanel::DbUtils::find_mysql();

        Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Object');

        # -B option for the mysql binary causes mysql to separate values with tabs.
        # -N Do not write column names in results.
        my $mysql_results = Cpanel::SafeRun::Object->new(
            'program' => $mysql_bin,
            'args'    => [ @preargs, '-B', '-A', @args ],
            'stdin'   => \"$cmd\n",
        );
        $did_select = $cmd =~ /^\s*(?:show|select)/i ? 1 : 0;

        $retcode = $mysql_results->CHILD_ERROR();

        if ( length $mysql_results->stderr() ) {

            # Hide warnings, but pass though errors
            $result .= join( "\n", grep( !m/^Warning:/, split( m{\n}, $mysql_results->stderr() ) ) );
        }
        $result .= $mysql_results->stdout();

        #Cpanel::Debug::log_warn("ran cmd: [$cmd] did_select=[$did_select] result=[$result]\n");
    }
    $result =~ s/\n$// if length $result;    #match Connect output

    if ( !$did_select && !length($result) && $retcode == 0 ) {
        $result = '0E0';
    }

    return $result;
}

1;
