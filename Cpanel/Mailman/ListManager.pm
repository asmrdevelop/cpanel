package Cpanel::Mailman::ListManager;

# cpanel - Cpanel/Mailman/ListManager.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AccessIds                    ();
use Cpanel::AccessIds::SetUids           ();
use Cpanel::TempFile                     ();
use Cpanel::Exception                    ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::AcctUtils::Account           ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::ConfigFiles                  ();
use Cpanel::FileUtils::Write             ();
use Cpanel::Mailman                      ();
use Cpanel::Mailman::Perms               ();
use Cpanel::Mailman::Filesys             ();
use Cpanel::Mailman                      ();
use Cpanel::Mailman::NameUtils           ();
use Cpanel::Locale                       ();
use Cpanel::SafeRun::Object              ();
use Cpanel::SafeRun::Errors              ();
use Cpanel                               ();
use Cpanel::Debug                        ();

my $locale;

our $ARCHIVE_REBUILD_TIMEOUT = 21600;    # 6 hours

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

sub regenerate_list {
    my ($list) = @_;

    my $MAILMAN_ARCHIVE_DIR = Cpanel::Mailman::Filesys::MAILMAN_ARCHIVE_DIR();

    $list = Cpanel::Mailman::NameUtils::normalize_name($list);

    my $config_regen_run = Cpanel::SafeRun::Object->new(
        'program'     => _withlist_program(),
        'args'        => [ '--lock', '--run', 'savelist', $list ],
        'user'        => $Cpanel::ConfigFiles::MAILMAN_USER,
        'homedir'     => $Cpanel::ConfigFiles::MAILMAN_ROOT,
        'timeout'     => 500,
        'before_exec' => sub {
            $ENV{'PYTHONPATH'} = '/usr/local/cpanel/lib/python2';
            require Cpanel::Timezones;
            $ENV{'TZ'} = Cpanel::Timezones::calculate_TZ_env();
            Cpanel::AccessIds::SetUids::setuids($Cpanel::ConfigFiles::MAILMAN_USER);
        }
    );

    if ( $config_regen_run->CHILD_ERROR() ) {

        my $error = _locale()->maketext( "[asis,Mailman] failed to regenerate the configuration for the list “[_1]” because of an error: [_2]", $list, join( q< >, map { $config_regen_run->$_() // () } qw( autopsy stderr stdout ) ) );
        warn $error;    # output into restore
        Cpanel::Debug::log_warn($error);
    }

    my $private_mbox_path = "$MAILMAN_ARCHIVE_DIR/$list.mbox/$list.mbox";
    if ( -e $private_mbox_path ) {
        my $archive_regen_run = Cpanel::SafeRun::Object->new(
            'program'     => _arch_program(),
            'args'        => [ '--quiet', $list ],
            'user'        => $Cpanel::ConfigFiles::MAILMAN_USER,
            'homedir'     => $Cpanel::ConfigFiles::MAILMAN_ROOT,
            'timeout'     => $ARCHIVE_REBUILD_TIMEOUT,
            'before_exec' => sub {
                $ENV{'PYTHONPATH'} = '/usr/local/cpanel/lib/python2';
                require Cpanel::Rlimit;
                require Cpanel::Timezones;
                Cpanel::Rlimit::set_rlimit_to_infinity();

                # Setting --quiet and TZ reduced the memory usage by 60%
                $ENV{'TZ'} = Cpanel::Timezones::calculate_TZ_env();
                Cpanel::AccessIds::SetUids::setuids($Cpanel::ConfigFiles::MAILMAN_USER);
            }
        );
        if ( $archive_regen_run->CHILD_ERROR() ) {
            my $error = _locale()->maketext( "[asis,Mailman] failed to regenerate the archives for the list “[_1]” because of an error: [_2]", $list, join( q< >, map { $archive_regen_run->$_() // () } qw( autopsy stderr stdout ) ) );
            warn $error;    # output into restore
            Cpanel::Debug::log_warn($error);
        }
    }

    return 1;
}

#This accepts a hashref with:
#   - list: The list name, either underscore- or at-sign-joined.
#       (e.g., coolkids_school.org OR coolkids@school.org)
#
sub fix_mailman_list_permissions {
    my ($args_hr) = @_;

    my $list = $args_hr->{'list'};
    die "Need “list”!" if !length $list;

    $list = Cpanel::Mailman::NameUtils::normalize_name($list);

    my $perms_obj = Cpanel::Mailman::Perms->new();

    if ( $perms_obj->set_perms_for_one_list($list) ) {
        Cpanel::Debug::log_warn("Failed to set permissions for mailing list: $list");
        return 0;
    }

    $perms_obj->set_archive_perms_for_one_list($list);

    return 1;

}

#----------------------------------------------------------------------
#Creates a mailman mailing list for a cpanel user (the owner)
#
#Required Named arguments:
#   - list
#       The name of the list to create.
#
#   - owner
#       The cpanel user that will own the list.
#
#   - domain
#       The domain that the list will use (must be owned
#       by the owner.
#
#   - pass
#       The password to use for mailman.
#
#Optional Named arguments:
#   - private
#       If true the list will be set to private.  If missing
#       or false, the list will be public.
#
#   - members
#       A scalar or scalarref new line separated
#       list of email addresses to add as members of the new list.
#
# TODO: members should likely be a separate function called
# subscribe_members
sub create_list {
    my (%OPTS) = @_;

    # Required
    my $list   = $OPTS{'list'};
    my $domain = $OPTS{'domain'};
    my $owner  = $OPTS{'owner'};
    my $pass   = $OPTS{'pass'};

    # Optional
    my $members = $OPTS{'members'};
    my $private = $OPTS{'private'};

    foreach my $param (qw(list domain owner pass)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $param ] ) if !length $OPTS{$param};
    }

    my $list_name     = Cpanel::Mailman::NameUtils::make_name( $list, $domain );
    my $list_address  = join( '@', $list,  $domain );
    my $owner_address = join( '@', $owner, $domain );

    if ( !Cpanel::Mailman::NameUtils::is_valid_name($list_name) ) {
        die( _locale()->maketext( '“[_1]” is not a valid name for a mailing list.', $list_address ) );
    }
    elsif ( !Cpanel::AcctUtils::Account::accountexists($owner) ) {
        die( _locale()->maketext( 'The user “[_1]” does not exist.', $owner ) );
    }
    elsif ( Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain) ne $owner ) {
        die( _locale()->maketext( 'The domain “[_1]” is not owned by “[_2]”.', $domain, $owner ) );
    }
    elsif ( Cpanel::Mailman::Filesys::does_list_exist( $list, $domain ) ) {
        die( _locale()->maketext( 'The mailing list “[_1]” is already configured.', $list_address ) );
    }

    my $return_string = Cpanel::AccessIds::do_as_user(
        'mailman',
        sub {
            ## case 47390: invoke newlist with a first arg of --stdin_passwd to trigger the read from STDIN
            my $run = Cpanel::SafeRun::Object->new(
                program => Cpanel::Mailman::Filesys::MAILMAN_DIR() . '/bin/newlist',
                args    => [ '--stdin_passwd', $list_name, $owner_address, $domain ],
                stdin   => $pass,
            );

            my $return_string = $run->stdout();

            $return_string .= apply_cp_mailman_selection( $list, $domain );

            # Make sure "${dir}/${list}/request.pck" is created
            require "$Cpanel::root/bin/checkmailmanrequests";    ## no critic qw(Modules::RequireBarewordIncludes)
            bin::checkmailmanrequests->run($list_name);

            if ($private) {                                      #aka PRIVATE flag
                my %opts = convert_privacy_opts_to_alter_list_privacy_args(%Cpanel::Mailman::OPTS_TO_SET_A_LIST_AS_PRIVATE);
                $run = Cpanel::SafeRun::Object->new(
                    program => "$Cpanel::root/bin/mailman_alter_list_privacy",
                    args    => [ $list_name, %opts ],
                );

                $return_string .= $run->stdout();
            }
            if ($members) {
                my $temp_obj  = Cpanel::TempFile->new();
                my $temp_file = $temp_obj->file();
                Cpanel::FileUtils::Write::overwrite_no_exceptions( $temp_file, $members, 0600 );
                $return_string .= Cpanel::SafeRun::Errors::saferunallerrors( "$Cpanel::ConfigFiles::MAILMAN_ROOT/bin/add_members", '-r', $temp_file, $list_name );
            }
            return $return_string;
        },
    );

    # Make sure mailman process starts if maillists exist, or stop when none exists.
    Cpanel::SafeRun::Object->new_or_die( 'program' => "$Cpanel::root/etc/init/checkmailman" );

    my $mm_obj = Cpanel::Mailman::Perms->new();
    $mm_obj->set_archive_perms_for_one_list($list_name);
    $mm_obj->set_perms_for_one_list($list_name);

    require "$Cpanel::root/scripts/update_mailman_cache";        ## no critic qw(Modules::RequireBarewordIncludes)
    scripts::update_mailman_cache->run( $owner, $list_name );    # will die on fail

    return $return_string;
}

sub apply_cp_mailman_selection {
    my ( $list, $domain ) = @_;

    my $program;

    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    if ( $cpconf_ref->{'usemailformailmanurl'} eq '1' ) {
        $program = 'cp_mailman_mail2';
    }
    else {
        $program = 'cp_mailman2';
    }

    my $run = Cpanel::SafeRun::Object->new(
        program => "$Cpanel::root/bin/$program",
        args    => [ $domain, $list ],
    );

    return $run->stdout();
}

sub convert_privacy_opts_to_alter_list_privacy_args {
    my (%args) = @_;

    return map { ( "--$_" => $args{$_} ) } keys %args;
}

#Args and return are the same as for Cpanel::SafeRun::Object()
#This function just adds a layer of error checking.
#
sub run_with_error_check {
    my (%args) = @_;

    my $run = Cpanel::SafeRun::Object->new(%args);

    if ( length $run->stderr() ) {
        die( $run->stderr() );
    }
    elsif ( $run->CHILD_ERROR() ) {
        die( $run->autopsy() );
    }

    return $run;
}

# For mocking
sub _withlist_program {
    return "$Cpanel::ConfigFiles::MAILMAN_ROOT/bin/withlist";
}

# For mocking
sub _arch_program {
    return "$Cpanel::ConfigFiles::MAILMAN_ROOT/bin/arch";
}

1;
