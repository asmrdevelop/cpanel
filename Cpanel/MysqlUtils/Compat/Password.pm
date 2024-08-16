package Cpanel::MysqlUtils::Compat::Password;

# cpanel - Cpanel/MysqlUtils/Compat/Password.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::MysqlUtils::Compat ();
use Cpanel::MysqlUtils::Quote  ();
use Cpanel::Database           ();

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Compat::Password

=head1 SYNOPSIS

use Cpanel::MysqlUtils::Compat::Password();

# If you have a DBH you can set a password for a user by:

Cpanel::MysqlUtils::Compat::Password::set_user_password_dbh( dbh => $dbh, user => 'bob', password => 'password', host => 'localhost');

# If you just need the raw SQL:

my $quoted_user     = Cpanel::MysqlUtils::Quote::quote($user);

my $quoted_password = Cpanel::MysqlUtils::Quote::quote($pass);

my $quoted_host     = Cpanel::MysqlUtils::Quote::quote($host);

Cpanel::MysqlUtils::Compat::Password::get_set_user_password_sql( quoted_user => $quoted_user, quoted_password => $quoted_password, quoted_host => $quoted_host );

=head1 DESCRIPTION

This module wraps up the logic for setting a MySQL password.

=head1 FUNCTIONS


=cut

my ( $_mysql_user_auth_field, $_has_password_expired, $_has_password_lifetime, $_needs_plugin_disabled, $_has_plugin );

my $default_plugin = 'mysql_native_password';

=head2 set_user_password_dbh( dbh => $dbh, user => $user, password => $password, [ host => $host, todo_before_flush_cr => $todo_cr ] )

This function sets a MySQL password for a specific user or user@host combination.

=head3 Arguments

=over 4

=item dbh    - Database handle - A database handle to the MySQL server.

=item user    - SCALAR - The username of the mysql user to change the password for

=item password    - SCALAR - The password to set for the specified MySQL user

=item host    - OPTIONAL SCALAR - This optional value is used to specify a specific host for the MySQL user.
                                  If no host is specified all combinations of user@host will be changed.

=item todo_before_flush_cr    - OPTIONAL CODEREF - This optional coderef is used to perform some action right before
                                                   calling flush privileges.

=back

=head3 Returns

This function returns 1 or dies.

=head3 Exceptions

This function can throw anything that the database connection can throw.

=cut

sub set_user_password_dbh {
    my (%OPTS) = @_;

    for (qw( dbh user password )) {
        die "Need $_!" if !$OPTS{$_};
    }

    my ( $dbh, $user, $password, $host, $todo_cr ) = @OPTS{qw( dbh user password host todo_before_flush_cr )};

    _handle_auth_plugin_if_needed_dbh( $dbh, $user, $host );

    _set_password_lifetime_if_needed( $dbh, $user, $host );

    _set_password_to_unexpired_if_needed( $dbh, $user, $host );

    _set_password_for_user_dbh( $dbh, $user, $password, $host );

    $todo_cr->($dbh) if $todo_cr;

    $dbh->do(q{FLUSH PRIVILEGES});

    return 1;
}

=head2 get_set_user_password_sql( quoted_user => $quote_user, quoted_password => $quoted_password, [ quoted_host => $quoted_host, force_plugin => 0 ] )

This function is used to get the SQL commands to reset a MySQL user password.
NOTE: This function does not return FLUSH PRIVILEGES as that is left up to the caller.

=head3 Arguments

=over 4

=item quoted_user    - SCALAR - The already quoted C<Cpanel::MysqlUtils::Quote::quote> username of the MySQL user to generate the SQL statements for.

=item quoted_password    - SCALAR - The already quoted C<Cpanel::MysqlUtils::Quote::quote> password of the MySQL user to generate the SQL statements for.

=item quoted_host    - OPTIONAL SCALAR - The already quoted C<Cpanel::MysqlUtils::Quote::quote> host of the MySQL user to generate the SQL statements for.

=item force_plugin   -  OPTIONAL BOOLEAN - If true the “plugin” column will be updated to the expected value without checking the current value.

=back

=head3 Returns

This function returns an arrayref of SQL statements to set the password for the specified user@host.
NOTE: FLUSH PRIVILEGES will not be returned as it is left up to the caller to call.

=head3 Exceptions

Dies if quote_user and quoted_password are not passed.

=cut

sub get_set_user_password_sql {
    my (%OPTS) = @_;

    for (qw( quoted_user quoted_password )) {
        die "Need $_!" if !$OPTS{$_};
    }

    my $opts = { map { $OPTS{$_} ? ( $_ => $OPTS{$_} ) : () } qw( quoted_user quoted_password quoted_host ) };
    $opts->{needs_host}   = $OPTS{quoted_host}  ? 1 : 0;
    $opts->{force_plugin} = $OPTS{force_plugin} ? 1 : 0;
    $opts->{dbi}          = $OPTS{dbi};

    my $sql_ar = [
        _get_auth_plugin_sql($opts),
        'FLUSH PRIVILEGES',
        _get_password_lifetime_sql($opts),
        _get_password_unexpire_sql($opts),
    ];

    push( @{$sql_ar}, _get_set_password_sql($opts) );

    return $sql_ar;
}

sub _set_password_to_unexpired_if_needed {
    my ( $dbh, $user, $host ) = @_;

    return if !_has_password_expired_support();

    $dbh->do( _get_password_unexpire_sql( { needs_host => length $host ? 1 : 0 } ), undef, $user, ( length $host ? $host : () ) );

    return;
}

sub _set_password_lifetime_if_needed {
    my ( $dbh, $user, $host ) = @_;

    return if !_has_password_lifetime_support();

    $dbh->do( _get_password_lifetime_sql( { needs_host => length $host ? 1 : 0 } ), undef, $user, ( length $host ? $host : () ) );

    return;
}

sub _set_password_for_user_dbh {
    my ( $dbh, $user, $password, $host ) = @_;

    my @sql = _get_set_password_sql( { needs_host => length $host ? 1 : 0 } );

    # There is a different calling syntax for when a host is specified to allow an error to be thrown
    # from MySQL/MariaDb if the user doesn't exist. See _get_set_password_sql for more info.
    if ( length $host ) {
        $dbh->do( $_, undef, $user, $host, $password ) for @sql;
    }
    else {
        $dbh->do( $_, undef, $password, $user ) for @sql;
    }

    return;
}

sub _handle_auth_plugin_if_needed_dbh {
    my ( $dbh, $user, $host ) = @_;

    return if !_has_plugin_support();

    $dbh->do( _get_auth_plugin_sql( { needs_host => length $host ? 1 : 0 } ), undef, $user, ( length $host ? $host : () ) );

    return;
}

sub _get_password_lifetime_sql {
    my ($opts) = @_;

    if ( !$opts->{quoted_host} && $opts->{quoted_user} ) {

        my $dbi = $opts->{'dbi'};
        if ( !$dbi ) {
            require Cpanel::MysqlUtils::Connect;
            $dbi = Cpanel::MysqlUtils::Connect::get_dbi_handle();
        }

        require Cpanel::MysqlUtils::Grants::Users;
        require Cpanel::MysqlUtils::Unquote;
        my $unquoted_user     = Cpanel::MysqlUtils::Unquote::unquote( $opts->{quoted_user} );
        my $user_hosts_map_hr = Cpanel::MysqlUtils::Grants::Users::get_all_hosts_for_users(
            $dbi,
            [$unquoted_user]
        );

        my @sqls;

        foreach my $host ( @{ $user_hosts_map_hr->{$unquoted_user} } ) {
            my $quoted_host = Cpanel::MysqlUtils::Quote::quote($host);
            push @sqls, Cpanel::Database->new()->get_password_lifetime_sql(
                quoted_user => $opts->{quoted_user},
                quoted_host => $quoted_host,
            );

        }

        return @sqls;
    }
    return Cpanel::Database->new()->get_password_lifetime_sql(%$opts);
}

sub _get_password_unexpire_sql {
    my ($opts) = @_;
    return Cpanel::Database->new()->get_password_unexpire_sql(%$opts);
}

# NOTE: This returns a LIST of statements!!
sub _get_set_password_sql {
    my ($opts) = @_;

    die 'I return a list!' if !wantarray;

    #NOTE: Ideally this would be done in a transaction,
    #but MySQL does an implicit commit on SET PASSWORD or ALTER USER.
    #cf. https://dev.mysql.com/doc/refman/5.5/en/implicit-commit.html

    my $quoted_user_or_bind     = $opts->{quoted_user}     || '?';
    my $quoted_host_or_bind     = $opts->{quoted_host}     || '?';
    my $quoted_password_or_bind = $opts->{quoted_password} || '?';

    if ( $opts->{quoted_user} && $opts->{quoted_host} ) {
        return Cpanel::Database->new()->get_set_password_sql( name => "$quoted_user_or_bind\@$quoted_host_or_bind", pass => $quoted_password_or_bind, exists => 1, hashed => 0, plugin => 0 );
    }
    elsif ( $opts->{quoted_user} && !$opts->{quoted_host} ) {

        my $dbi = $opts->{'dbi'};
        if ( !$dbi ) {
            require Cpanel::MysqlUtils::Connect;
            $dbi = Cpanel::MysqlUtils::Connect::get_dbi_handle();
        }
        require Cpanel::MysqlUtils::Grants::Users;
        require Cpanel::MysqlUtils::Unquote;
        my $unquoted_user     = Cpanel::MysqlUtils::Unquote::unquote( $opts->{quoted_user} );
        my $user_hosts_map_hr = Cpanel::MysqlUtils::Grants::Users::get_all_hosts_for_users(
            $dbi,
            [$unquoted_user]
        );

        my @alter_user;

        # we need these as backticks, but also deal with question
        # mark
        my $quoted_user = ( $quoted_user_or_bind eq '?' ) ? $quoted_user_or_bind : Cpanel::MysqlUtils::Quote::quote_identifier($unquoted_user);

        foreach my $host ( @{ $user_hosts_map_hr->{$unquoted_user} } ) {

            my $quoted_host = Cpanel::MysqlUtils::Quote::quote($host);
            my $exists      = Cpanel::Database->new()->user_exists( $quoted_user, $quoted_host );
            push @alter_user, Cpanel::Database->new()->get_set_password_sql(
                name   => "$quoted_user\@$quoted_host",
                pass   => $quoted_password_or_bind,
                exists => $exists,
                hashed => 0,
                plugin => 0,
            );
        }

        return @alter_user;
    }

    return Cpanel::Database->new()->get_set_password_sql(
        name   => "$quoted_user_or_bind\@$quoted_host_or_bind",
        pass   => $quoted_password_or_bind,
        exists => 1,
        hashed => 0,
        plugin => 0,
    );
}

sub _get_auth_plugin_sql {
    my ($opts) = @_;

    return if !_has_plugin_support();
    if ( _needs_plugin_disabled() ) {
        return _get_disable_auth_plugin_sql($opts);
    }
    else {
        return _get_enable_default_auth_plugin_sql($opts);
    }
}

sub _get_enable_default_auth_plugin_sql {
    my ($opts) = @_;
    return Cpanel::Database->new()->get_enable_default_auth_plugin_sql(%$opts);
}

sub _get_disable_auth_plugin_sql {
    my ($opts) = @_;
    return Cpanel::Database->new()->get_disable_auth_plugin_sql(%$opts);
}

sub _has_password_expired_support {
    return $_has_password_expired //= Cpanel::MysqlUtils::Compat::has_password_expired_support();
}

sub _has_password_lifetime_support {
    return $_has_password_lifetime //= Cpanel::MysqlUtils::Compat::has_password_lifetime_support();
}

sub _has_plugin_support {
    return $_has_plugin //= Cpanel::MysqlUtils::Compat::has_plugin_support();
}

sub _needs_plugin_disabled {
    return $_needs_plugin_disabled //= Cpanel::MysqlUtils::Compat::needs_password_plugin_disabled();
}

# For testing
sub clear_cache {
    undef $_mysql_user_auth_field;
    undef $_has_password_expired;
    undef $_has_password_lifetime;
    undef $_needs_plugin_disabled;
    undef $_has_plugin;

    return;
}

1;
