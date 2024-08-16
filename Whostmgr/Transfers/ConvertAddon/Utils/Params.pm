package Whostmgr::Transfers::ConvertAddon::Utils::Params;

# cpanel - Whostmgr/Transfers/ConvertAddon/Utils/Params.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception        ();
use Cpanel::LoadModule       ();
use Cpanel::DB::Prefix::Conf ();

my $params;

sub required_value_params {
    return ( sort keys %{ params()->{'required'}->{'string'} } );
}

sub optional_flag_params {
    return ( sort keys %{ params()->{'optional'}->{'flag'} } );
}

sub optional_value_params {
    return ( sort keys %{ params()->{'optional'}->{'string'} } );
}

sub validate_required_params {
    my $args = shift;

    Cpanel::LoadModule::load_perl_module('Cpanel::Validate::Domain');
    Cpanel::LoadModule::load_perl_module('Whostmgr::Accounts::NameConflict');
    Cpanel::LoadModule::load_perl_module('Whostmgr::Transfers::ConvertAddon::Utils');
    my $validation_tests = {
        'username' => sub { return Whostmgr::Accounts::NameConflict::verify_new_name( $_[0] ); },
        'domain'   => sub {
            Cpanel::Validate::Domain::valid_domainname_for_customer_or_die( $_[0] );
            my $details = Whostmgr::Transfers::ConvertAddon::Utils::get_addon_domain_details( $_[0] );
            die Cpanel::Exception::create( 'DomainDoesNotExist', 'The addon domain “[_1]” does not exist.', [ $_[0] ] )
              if 'HASH' ne ref $details;
            die Cpanel::Exception->create( 'Subdomains exist on the addon domain “[_1]”.', [ $_[0] ] )
              if $details->{'subdomains'} && 'ARRAY' eq ref $details->{'subdomains'} && scalar @{ $details->{'subdomains'} };
            die Cpanel::Exception->create( 'The addon domain “[_1]” has an [asis,IPv6] address assigned.', [ $_[0] ] )
              if $details->{'ipv6'};
            return 1;
        },
        'pkgname' => sub {
            require Whostmgr::Packages::Fetch;

            my $package_hr = Whostmgr::Packages::Fetch::fetch_package_list( 'want' => 'creatable', 'package' => $_[0] );
            die Cpanel::Exception::create( 'InvalidParameter', 'Verify that the package “[_1]” exists and you have not exceeded your reseller restrictions.', [ $_[0] ] )
              if !exists $package_hr->{ $_[0] };

            # If the package assigns a dedicated IP address, then
            # we need to check and see if the system has any free IPs
            # so that the create account call does not fail for this
            # reason alone.
            if ( exists $package_hr->{ $_[0] }{'IP'} && $package_hr->{ $_[0] }{'IP'} eq 'y' ) {
                Cpanel::LoadModule::load_perl_module('Whostmgr::ACLS');
                if ( !Whostmgr::ACLS::hasroot() ) {
                    Cpanel::LoadModule::load_perl_module('Cpanel::ResellerFunctions');
                    my $reselleracl_ref = Cpanel::ResellerFunctions::getreselleraclhash( $ENV{'REMOTE_USER'} );
                    die Cpanel::Exception->create( 'You must have the “[_1]” privilege to create an account with a dedicated [asis,IP] address.', ['add-pkg-ip'] )
                      if !( grep( m{ \A all \z }xms, @{$reselleracl_ref} ) || grep( m{ \A add-pkg-ip \z }xms, @{$reselleracl_ref} ) );
                }

                require Cpanel::DIp::Group;
                my $free_ips = Cpanel::DIp::Group::get_available_ips();
                die Cpanel::Exception->create('This package requires a dedicated [asis,IP] address, but this system has no free [asis,IP] addresses.')
                  if !( $free_ips && 'ARRAY' eq ref $free_ips && scalar @{$free_ips} );
            }
            return [];
        },
    };

    my @err_collection;
    foreach my $required_key ( required_value_params() ) {
        if ( not defined $args->{$required_key} ) {
            push @err_collection, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$required_key] );
        }
        elsif ( exists $validation_tests->{$required_key} && !eval { $validation_tests->{$required_key}->( $args->{$required_key} ); } ) {
            push @err_collection, Cpanel::Exception::create(
                'InvalidParameter',
                'Invalid configuration for the parameter “[_1]”: [_2]',
                [ $required_key, Cpanel::Exception::get_string( $@, 'no_id' ) ]
            );
        }
    }
    return \@err_collection;
}

# This requires the $ENV{'REMOTE_USER'} and ACLS to be populated.
#
# The two contexts where it runs atm, guarantee this:
# 1) xml-api
# 2) convert_addon_to_account CLI script
sub validate_optional_value_params {
    my ( $args, $migrate_opts ) = @_;

    my $validation_tests = {
        'email-address' => sub {
            Cpanel::LoadModule::load_perl_module('Cpanel::Validate::EmailRFC');
            die Cpanel::Exception->create( 'The email address “[_1]” is not valid.', [ $_[0] ] )
              if !Cpanel::Validate::EmailRFC::is_valid( $_[0] );
            return [];
        },
        'notify-user' => sub {
            Cpanel::LoadModule::load_perl_module('Whostmgr::ACLS');
            Cpanel::LoadModule::load_perl_module('Cpanel::Validate::Username');

            Cpanel::Validate::Username::user_exists_or_die( $_[0] );
            return [] if Whostmgr::ACLS::hasroot();

            Cpanel::LoadModule::load_perl_module('Whostmgr::Authz');
            Whostmgr::Authz::verify_account_access( $_[0] );
            return [];
        },
        'copy-mysqldb'   => sub { _validate_copy_mysqldb_params(@_); },
        'move-mysqldb'   => sub { _validate_move_mysqldb_params(@_); },
        'move-mysqluser' => sub { _validate_move_mysqluser_params(@_); },
    };

    my @err_collection;
    foreach my $optional_key ( optional_value_params() ) {

        # skip if its an empty array or an empty string;
        next if !( ( 'ARRAY' eq ref $args->{$optional_key} && scalar @{ $args->{$optional_key} } ) || length $args->{$optional_key} );
        if ( exists $validation_tests->{$optional_key} ) {
            my $exceptions = eval { $validation_tests->{$optional_key}->( $args->{$optional_key}, $migrate_opts ); };
            if ($@) {
                push @err_collection, Cpanel::Exception::create(
                    'InvalidParameter',
                    'Invalid configuration for “[_1]”: [_2]',
                    [ $optional_key, Cpanel::Exception::get_string( $@, 'no_id' ) ]
                );
                next;
            }
            push @err_collection, @{$exceptions};
        }
    }
    return \@err_collection;
}

sub help_msg {
    return <<USAGE;
$0

Utility to convert Addon Domains into standalone cPanel accounts.

Required options:

${ \_required_help_text() }
Optional:

${ \_optional_help_text() }
Other options:

    --help
        Displays this help message.

USAGE
}

sub _required_help_text {
    my $string;

    my $required_params = params()->{'required'}->{'string'};
    foreach my $param ( sort keys %{$required_params} ) {
        $string .= "    --${param} " . ( join ' ', map { "<$_>" } @{ $required_params->{$param}->{'params'} } ) . "\n";
        $string .= "        $required_params->{$param}->{'desc'}\n\n";
    }

    chomp $string;
    return $string;
}

sub _optional_help_text {
    my $string;

    my $optional_flag_params = params()->{'optional'}->{'flag'};
    foreach my $param ( sort keys %{$optional_flag_params} ) {
        $string .= "    --[no]${param}\n";
        $string .= "        $optional_flag_params->{$param}->{'desc'}." . " Default: $optional_flag_params->{$param}->{'default'}\n\n";
    }

    my $optional_value_params = params()->{'optional'}->{'string'};
    foreach my $param ( sort keys %{$optional_value_params} ) {
        $string .= "    --${param} " . ( join ' ', map { "<$_>" } @{ $optional_value_params->{$param}->{'params'} } ) . "\n";
        $string .= "        $optional_value_params->{$param}->{'desc'}.\n";
        $string .= "        Can be specified multiple times\n" if $optional_value_params->{$param}->{'multiple'};
        $string .= "\n";
    }

    chomp $string;
    return $string;
}

sub _validate_copy_mysqldb_params {
    my ( $db_args, $owner_info ) = @_;

    if ( $db_args && 'HASH' ne ref $db_args ) {
        if ( ( 'ARRAY' eq ref $db_args ) && ( scalar( @{$db_args} ) % 2 == 0 ) ) {
            $db_args = { @{$db_args} };
        }
        else {
            return Cpanel::Exception::create( 'MissingParameter', 'You must provide a [asis,hashref] containing details database copy operation' );    ## no extract maketext (developer error message. no need to translate)
        }
    }

    my @err_collection;
    push @err_collection, _check_dbowner_info($owner_info);
    return \@err_collection if scalar @err_collection;

    Cpanel::LoadModule::load_perl_module('Cpanel::DB::Prefix');
    require Cpanel::Validate::DB::Name;
    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Connect');
    my $counts = {};
    foreach my $db_name ( keys %{$db_args} ) {
        my $db_copy = $db_args->{$db_name};
        $counts->{$db_copy}++;

        my $bad_name = 0;
        if ( !$db_copy || $db_copy eq $db_name || $counts->{$db_copy} > 1 ) {
            push @err_collection, Cpanel::Exception::create(
                'InvalidParameter',
                'A unique database name must be specified in order to copy the “[_1]” database',
                [$db_name]
            );
            $bad_name++;
        }
        elsif ( !eval { Cpanel::Validate::DB::Name::verify_mysql_database_name($db_copy); 1; } ) {
            push @err_collection, $@;
            $bad_name++;
        }
        elsif ( Cpanel::DB::Prefix::Conf::use_prefix() ) {
            my $prefixed_dbname = Cpanel::DB::Prefix::add_prefix_if_name_needs( $owner_info->{'to_username'}, $db_copy );
            if ( $prefixed_dbname ne $db_copy ) {
                push @err_collection, Cpanel::Exception->create(
                    'The name “[_1]” does not begin with the required prefix “[_2]”.',
                    [ $db_copy, Cpanel::DB::Prefix::username_to_prefix( $owner_info->{'to_username'} ) . '_' ]
                );
                $bad_name++;
            }
        }
        next if $bad_name;

        my $dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle();
        if ( $dbh->db_exists($db_copy) ) {
            push @err_collection, Cpanel::Exception->create( 'The [asis,MySQL] database “[_1]” already exists.', [$db_copy] );
        }
        elsif ( !eval { _user_owns( { 'dbname' => $db_name, 'username' => $owner_info->{'from_username'} } ); } ) {
            push @err_collection, $@ if $@;
        }
    }

    return \@err_collection;
}

sub _validate_move_mysqldb_params {
    my ( $db_args, $owner_info ) = @_;

    my @err_collection;
    push @err_collection, _check_dbowner_info($owner_info);
    return \@err_collection if scalar @err_collection;

    foreach my $db_name ( @{$db_args} ) {
        if ( !eval { _user_owns( { 'dbname' => $db_name, 'username' => $owner_info->{'from_username'} } ); } ) {
            push @err_collection, $@ if $@;
        }
    }

    return \@err_collection;
}

sub _validate_move_mysqluser_params {
    my ( $db_args, $owner_info ) = @_;

    my @err_collection;
    push @err_collection, _check_dbowner_info($owner_info);
    return \@err_collection if scalar @err_collection;

    foreach my $db_user ( @{$db_args} ) {
        if ( !eval { _user_owns( { 'dbusername' => $db_user, 'username' => $owner_info->{'from_username'} } ); } ) {
            push @err_collection, $@ if $@;
        }
    }

    return \@err_collection;
}

sub _check_dbowner_info {
    my $owner_info = shift;

    if ( 'HASH' ne ref $owner_info || !( length $owner_info->{'from_username'} && length $owner_info->{'to_username'} ) ) {
        return Cpanel::Exception::create( 'MissingParameter', 'You must provide a [asis,hashref] containing details about the Addon Conversion' );    ## no extract maketext (developer error message. no need to translate)
    }

    return;
}

sub _user_owns {
    my $opts = shift;

    Cpanel::LoadModule::load_perl_module('Cpanel::DB::Map::Reader');
    my $map = Cpanel::DB::Map::Reader->new( cpuser => $opts->{'username'}, engine => 'mysql' );
    if ( $opts->{'dbname'} ) {
        $map->database_exists( $opts->{'dbname'} )
          || die Cpanel::Exception->create( 'The system user “[_1]” does not control a MySQL database named “[_2]”.', [ $opts->{'username'}, $opts->{'dbname'} ] );
    }
    elsif ( $opts->{'dbusername'} ) {
        $map->dbuser_exists( $opts->{'dbusername'} )
          || die Cpanel::Exception->create( 'The system user “[_1]” does not control a MySQL user named “[_2]”.', [ $opts->{'username'}, $opts->{'dbusername'} ] );
    }

    return 1;
}

sub params {
    $params //= {
        'required' => {
            'string' => {
                'domain' => {
                    'desc'     => 'The Addon Domain to convert into a standalone cPanel account',
                    'required' => 1,
                    'params'   => [qw(addon-domain)],
                },
                'username' => {
                    'desc'     => 'The username for the new standalone cPanel account',
                    'required' => 1,
                    'params'   => [qw(new-username)],
                },
                'pkgname' => {
                    'desc'     => 'The hosting package to assign to the new account',
                    'required' => 1,
                    'params'   => [qw(package-name)],
                },
            },
        },
        'optional' => {
            'flag' => {
                'remove-subdomain' => {
                    'desc'    => 'Remove the subdomain associated with the addon domain from the origin account',
                    'default' => 1,
                },
                'email-forwarders' => {
                    'desc'    => 'Move the Email Forwarders (includes Domain Forwarders) for the Addon Domain',
                    'default' => 1,
                },
                'custom-dns-records' => {
                    'desc'    => 'Move any custom DNS records for the Addon Domain',
                    'default' => 1,
                },
                'docroot' => {
                    'desc'    => 'Copy the Document Root for the Addon Domain',
                    'default' => 1,
                },
                'email-accounts' => {
                    'desc'    => 'Copy the Email Accounts and Email Filters for the Addon Domain',
                    'default' => 1,
                },
                'autoresponders' => {
                    'desc'    => 'Copy the Autoresponders for the Addon Domain',
                    'default' => 1,
                },
                'daemonize' => {
                    'desc'    => 'Run the conversion in the background, safe from terminal closures',
                    'default' => 0,
                },
                'preserve-ownership' => {
                    'desc'    => 'Create the new account with the same owner as the origin account',
                    'default' => 1,
                },
                'custom-vhost-includes' => {
                    'desc'    => 'Copy the custom VirtualHost includes for the Addon Domain',
                    'default' => 1,
                },
                'copy-installed-ssl-cert' => {
                    'desc'    => 'Copy the installed SSL Certificate for the Addon Domain',
                    'default' => 1,
                },
                'ftp-accounts' => {
                    'desc'    => 'Copy the FTP Accounts for the Addon Domain',
                    'default' => 1,
                },
                'webdisk-accounts' => {
                    'desc'    => 'Copy the Web Disk Accounts for the Addon Domain',
                    'default' => 1,
                },
                'calendar-sharing' => {
                    'desc'    => 'Copy any existing calendar shares within the Addon Domain',
                    'default' => 1,
                }
            },
            'string' => {
                'email-address' => {
                    'desc'   => 'Specify the contact email address to set on the new account',
                    'params' => [qw(email-address)],
                },
                'copy-mysqldb' => {
                    'desc'     => 'Copy the specified MySQL database from the source account into the new account under a new name',
                    'params'   => [qw(old-database-name new-database-name)],
                    'multiple' => 1,
                },
                'move-mysqldb' => {
                    'desc'     => 'Move the specified MySQL database from the source account into the new account',
                    'params'   => [qw(database-name)],
                    'multiple' => 1,
                },
                'move-mysqluser' => {
                    'desc'     => 'Move the specified MySQL user from the source account into the new account',
                    'params'   => [qw(database-username)],
                    'multiple' => 1,
                },
                'notify-user' => {
                    'desc'   => 'Specify the cPanel user to notify upon completion',
                    'params' => [qw(cpanel-username)],
                }
            }
        }
    };

    return $params;
}

1;
