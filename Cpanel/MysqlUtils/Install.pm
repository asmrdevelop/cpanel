package Cpanel::MysqlUtils::Install;

# cpanel - Cpanel/MysqlUtils/Install.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Parser::Callback          ();
use Cpanel::CPAN::IO::Callback::Write ();
use Cpanel::SafeRun::Object           ();
use Cpanel::Output::Legacy            ();
use Cpanel::MysqlUtils::Versions      ();

#A special list of providees that Cpanel::Repo::Install will uninstall
#via rpm --nodeps prior to the YUM operations. This allows us to upgrade
#MySQL without also uninstalling MyDNS (now removed from the product),
# which depends on MySQL. For most
#things this would be solvable by doing the yum operations in a single
#transaction (i.e., via yum shell); however, MariaDB specifically
#blocks that from happening. So, here’s this.
use constant NO_DEPS_PRE_UNINSTALLS => (
    'mysql-server',
);

our $CHECK_CPANEL_RPMS_PROG = '/usr/local/cpanel/scripts/check_cpanel_pkgs';
our $BUILD_MYSQL_CONF_PROG  = '/usr/local/cpanel/bin/build_mysql_conf';

###########################################################################
#
# Method:
#   new
#
# Description:
#   This module create an Cpanel::MysqlUtils::Install object
#   which is used to install MySQL rpms along with the
#   legacy MySQL compatibility RPMs.
#
# Parameters:
#   output_obj   - A Cpanel::Output object
#
# Returns:
#   A Cpanel::MysqlUtils::Install object
#
sub new {
    my ( $class, %OPTS ) = @_;

    return bless { 'output_obj' => ( $OPTS{'output_obj'} || Cpanel::Output::Legacy->new() ) }, $class;
}

sub ensure_rpms {
    my ($self) = @_;

    # Run one more time to make sure the -compat packages get installed
    # as we may have had to remove MariaDB-compat
    $self->_callback_run(
        'program' => $CHECK_CPANEL_RPMS_PROG,

        # In this case no need to check the md5/sha1 of each file as we only want to ensure they are installed here so we use --no-digest
        'args'          => [ '--targets=' . ( join ',', Cpanel::MysqlUtils::Versions::get_rpm_target_names() ), '--fix', '--no-broken', '--no-digest' ],
        'error_message' => 'Failed to update package',
    );
    return 1;
}

sub build_mysql_conf {
    my ($self) = @_;

    $self->{'output_obj'}->out("Building configuration.");
    $self->{'output_obj'}->out("This step may produce some errors or warnings in the log. The errors are usually harmless and are a result of table changes between versions of MySQL or MariaDB.");
    $self->_callback_run(
        'program'       => $BUILD_MYSQL_CONF_PROG,
        'error_message' => 'Failed to build the configuration.',
    );
    $self->{'output_obj'}->out("Done building configuration.");
    return 1;
}

sub _callback_run {
    my ( $self, %OPTS ) = @_;

    my $error_message = delete $OPTS{'error_message'};
    my $output        = $self->{'output_obj'};

    $output->out( "Running: $OPTS{'program'}" . ( $OPTS{'args'} ? ' ' . join( ' ', @{ $OPTS{'args'} } ) : '' ) );

    my $callback_obj = Cpanel::Parser::Callback->new( 'callback' => sub { $output->out(@_) } );
    my $saferun      = Cpanel::SafeRun::Object->new(
        %OPTS,
        'stdout' => Cpanel::CPAN::IO::Callback::Write->new(
            sub {
                my ($data) = @_;
                return $callback_obj->process_data($data);
            }
        ),
    );

    $callback_obj->finish();

    if ( $saferun->CHILD_ERROR() ) {
        die "$error_message: " . $saferun->stderr() . ':' . $saferun->autopsy();
    }
    return 1;
}

1;
