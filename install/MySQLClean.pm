package Install::MySQLClean;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use parent qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::SafeRun::Simple          ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::Services::Enabled        ();
use Cpanel::PwCache                  ();    # PPI USE OK - For MyCnf::Basic
use Cpanel::MysqlUtils::Connect      ();
use Cpanel::MysqlUtils::Secure       ();

use Try::Tiny;

our $VERSION = '1.1';

=head1 DESCRIPTION

    This task only run when using a local MySQL server
    on a regular cPanel license. (not for dnsonly).

    Run scripts/securemysql and apply a few extra MySQL tweaks.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('mysqlclean');
    $self->add_dependencies(qw(pre));

    return $self;
}

sub _check_mysql {
    my $err;

    my $host = Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost();

    my $ok;

    require Cpanel::MysqlUtils::Unprivileged;

    try {
        Cpanel::MysqlUtils::Unprivileged::get_version_from_host($host);
        $ok = 1;
    }
    catch {
        my $err = $_;
        warn "Failed to connect to MySQL/MariaDB: Restarting service …\n";

        # If we cannot connect to mysql we need to restart it to get it functional
        # use --force to ensure stop and start, as restart might be blocked
        Cpanel::SafeRun::Simple::saferun( q{/usr/local/cpanel/scripts/restartsrv_mysql}, qw{--force --no-verbose} );
        if ($?) {
            warn "Restart of MySQL/MariaDB failed (CHILD_ERROR=$?)\n\n$err\n";
        }
        else {
            $ok = 1;
        }
    };

    return $ok || 0;
}

sub perform {
    my $self = shift;

    return 1 if Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql();
    return 1 unless Cpanel::Services::Enabled::is_enabled('mysql');

    # as this task use pre as a dependency, if MySQL is down, all other install tasks are skipped
    # XXX: Should a _check_mysql() failure make us skip the rest of this?
    _check_mysql();

    my $dbh        = Cpanel::MysqlUtils::Connect::get_dbi_handle();
    my $actions_hr = {
        'securemycnf'        => 1,
        'removeanon'         => 1,
        'removetestdb'       => 1,
        'removelockntmp'     => 1,
        'removepublicgrants' => 1,
    };
    my $verbose = 1;

    Cpanel::MysqlUtils::Secure::perform_secure_actions( $dbh, $actions_hr, $verbose );

    return 1;
}

1;

__END__
