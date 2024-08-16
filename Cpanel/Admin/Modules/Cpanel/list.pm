
# cpanel - Cpanel/Admin/Modules/Cpanel/list.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::list;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Config::LoadCpConf ();
use Cpanel::Exception          ();
use Cpanel::Mailman::NameUtils ();
use Cpanel::SafeFile           ();
use Cpanel::SafeFile::Replace  ();
use Cpanel::SafeRun::Simple    ();
use Cpanel::Autodie            ();
use Cpanel::FileUtils::Write   ();

my $locale;

sub _locale {
    require Cpanel::Locale;
    return $locale ||= Cpanel::Locale->get_handle();
}

sub _actions {
    return qw(
      RECACHE_CONFIGURATION
      CREATE_LIST
      CREATE_TEMPORARY_PASSWORD
      DELETE_LIST
      SET_PASSWORD
      SET_PRIVACY
      ADD_ADDRESSES_TO_LISTOWNER
      DELETE_ADDRESSES_FROM_LISTOWNER
      EXPORT_LISTS
    );
}

sub _init {
    my ($self) = @_;

    $self->cpuser_has_feature_or_die('lists');

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    if ( $cpconf->{'skipmailman'} ) {
        die Cpanel::Exception::create( 'AdminError', [ message => _locale()->maketext("The administrator has disabled Mailman mailing lists.") ] );
    }

    $self->{'_cpconf'} = $cpconf;

    return;
}

sub _check_domain {
    my ( $self, $domain ) = @_;

    if ( !length $domain ) {
        $domain = $self->get_cpuser_domains()->[0];
    }

    $self->verify_that_cpuser_owns_domain($domain);

    return $domain;
}

sub _check_list {
    my ( $self, $list, $domain ) = @_;

    if ( !length $list ) {
        die Cpanel::Exception::create( 'AdminError', [ message => _locale()->maketext('The system cannot continue because you did not specify a mailing list.') ] );
    }

    if ( !Cpanel::Mailman::NameUtils::is_valid_name( Cpanel::Mailman::NameUtils::make_name( $list, $domain ) ) ) {
        die Cpanel::Exception::create( 'AdminError', [ message => _locale()->maketext( '“[_1]” is not a valid name for a mailing list.', $list ) ] );
    }

    return $list;
}

sub _verify_list_name_and_domain {
    my ( $self, $list, $domain ) = @_;

    $domain = $self->_check_domain($domain);
    $self->_check_list( $list, $domain );

    require Cpanel::Mailman::Filesys;
    if ( !Cpanel::Mailman::Filesys::does_list_exist( $list, $domain ) ) {
        die Cpanel::Exception::create( 'AdminError', [ message => _locale()->maketext( 'You do not have a mailing list named “[_1]”.', "$list\@$domain" ) ] );
    }

    return ( $list, $domain );
}

#Positional args:
#   list name
#   password
#   list domain
sub SET_PASSWORD {
    my ( $self, $list, $pass, $domain ) = @_;

    ( $list, $domain ) = $self->_verify_list_name_and_domain( $list, $domain );

    $self->_verify_password($pass);

    require Cpanel;
    my $reset_bin = "$Cpanel::root/bin/reset_mailman_passwd2";

    require Cpanel::AccessIds;
    require Cpanel::Mailman::ListManager;
    my $stdout = Cpanel::AccessIds::do_as_user(
        'mailman',
        sub {

            ## case 47390: functionality for 'change list password' goes through python, which
            ##   modifies the appropriate config.pck directly (password sent via STDIN)
            my $run = Cpanel::Mailman::ListManager::run_with_error_check(
                program => $reset_bin,
                args    => [ $list . '_' . $domain ],
                stdin   => $pass,
            );

            return $run->stdout();
        },
    );

    if ( $? >> 8 ) {
        require Cpanel::ChildErrorStringifier;
        my $child_error_string = Cpanel::ChildErrorStringifier->new($?);
        $child_error_string->set_program($reset_bin);
        die $child_error_string->autopsy();
    }

    return $stdout;
}

sub _verify_password {
    my ( $self, $pass ) = @_;

    if ( !length $pass ) {
        die Cpanel::Exception::create( 'AdminError', [ message => _locale()->maketext('The system cannot continue because you did not provide a password.') ] );
    }

    return;
}

#Positional args:
#   list name
#   password
#   list domain
#   boolean: Whether to make the list private (default: off)
sub CREATE_LIST {
    my ( $self, $list, $pass, $domain, $will_list_be_private ) = @_;

    $domain = $self->_check_domain($domain);
    $self->_check_list( $list, $domain );
    $self->_verify_password($pass);

    require Cpanel::Config::LoadCpUserFile;
    my $cpuser_hr = Cpanel::Config::LoadCpUserFile::load( $self->get_caller_username() );
    my $maxlst =
      !length $cpuser_hr->{'MAXLST'} || $cpuser_hr->{'MAXLST'} =~ m/unlimited/i
      ? 'unlimited'
      : int $cpuser_hr->{'MAXLST'};

    if ( length($maxlst) && $maxlst !~ /unlimited/i ) {
        if ( $maxlst <= @{ $self->_listlists() } ) {
            die Cpanel::Exception::create( 'AdminError', [ message => _locale()->maketext('Your account exceeds the maximum allowed mailing lists.') ] );
        }
    }

    require Cpanel::Mailman::ListManager;
    return Cpanel::Mailman::ListManager::create_list(
        'list'    => $list,
        'domain'  => $domain,
        'owner'   => $self->get_caller_username(),
        'pass'    => $pass,
        'private' => $will_list_be_private,
    );
}

#Positional args:
#   list name
#   list domain
sub DELETE_LIST {
    my ( $self, $list, $domain ) = @_;

    #Fail if we try to delete a nonexistent list, since we need to
    #tell the caller of a potential problem.
    ( $list, $domain ) = $self->_verify_list_name_and_domain( $list, $domain );

    require Cpanel::AccessIds;
    require Cpanel::Mailman::Filesys;
    require Cpanel::Mailman::ListManager;
    my $return_string = Cpanel::AccessIds::do_as_user(
        'mailman',
        sub {
            my $run = Cpanel::Mailman::ListManager::run_with_error_check(
                program => Cpanel::Mailman::Filesys::MAILMAN_DIR() . '/bin/rmlist',
                args    => [ '-a', $list . '_' . $domain ],
            );
            my $return_string = $run->stdout();

            return $return_string;
        }
    );

    # Make sure mailman process starts if maillists exist, or stop when none exists.
    # This must be done as root in order to create flag files if needed
    # If there are no more lists this may report exit 1 so
    # we do not die_on_error
    require Cpanel;
    require Cpanel::SafeRun::Object;
    my $run = Cpanel::SafeRun::Object->new( 'program' => "$Cpanel::root/etc/init/checkmailman" );
    $return_string .= $run->stdout();

    require Cpanel::Mailman::Perms;
    my $mm_obj = Cpanel::Mailman::Perms->new();
    $mm_obj->set_archive_perms_for_one_list("$list\_$domain");
    $mm_obj->set_perms_for_one_list("$list\_$domain");

    require "$Cpanel::root/scripts/update_mailman_cache";    ## no critic qw(Modules::RequireBarewordIncludes)

    scripts::update_mailman_cache->run( $self->get_caller_username(), "$list\_$domain" );    # will die on fail

    return $return_string;
}

#Positional args:
#   list name
#   list domain
sub CREATE_TEMPORARY_PASSWORD {
    my ( $self, $list, $domain ) = @_;

    ( $list, $domain ) = $self->_verify_list_name_and_domain( $list, $domain );

    my $list_name = $list . '_' . $domain;

    require Cpanel::Cpses::Mailman;
    my ( $status, $ret ) = Cpanel::Cpses::Mailman::generate_mailman_otp($list_name);

    # Don’t expose this error since we don’t know anything about it.
    die $ret if !$status;

    return $ret;
}

#Named arguments:
#   list_name
#   list_domain
#   ( @privacy_opts )
#
sub SET_PRIVACY {
    my ( $self, %args ) = @_;

    my @name_domain = delete @args{qw( list_name  list_domain )};

    @name_domain = $self->_verify_list_name_and_domain(@name_domain);

    my $full_list_name = join( '@', @name_domain );

    require Cpanel::Mailman;
    my @privacy_opts = keys %Cpanel::Mailman::OPTS_TO_SET_A_LIST_AS_PRIVATE;

    my %valid_arg_check = map { $_ => undef } @privacy_opts;

    if ( grep { !exists $valid_arg_check{$_} } keys %args ) {
        die Cpanel::Exception::create( 'AdminError', [ message => "Invalid args: " . join( ',', %args ) ] );
    }

    require Cpanel::Mailman::ListManager;
    my %cmd_args = Cpanel::Mailman::ListManager::convert_privacy_opts_to_alter_list_privacy_args(%args);

    require Cpanel;
    my $run = Cpanel::Mailman::ListManager::run_with_error_check(
        program => "$Cpanel::root/bin/mailman_alter_list_privacy",
        args    => [ $full_list_name, %cmd_args ],
    );

    return;
}

sub _manage_listowner_addresses {
    my ( $self, $action, $args ) = @_;

    my @name_domain = delete @{$args}{qw( list_name  list_domain )};

    @name_domain = $self->_verify_list_name_and_domain(@name_domain);

    my $full_list_name = join( '@', @name_domain );

    if ( !$args->{'addresses'} || ref $args->{'addresses'} ne 'ARRAY' ) {
        die Cpanel::Exception::create( 'AdminError', [ message => "“addresses” must be an array of email addresses." ] );
    }

    require Cpanel::Validate::EmailCpanel;
    foreach my $email ( @{ $args->{'addresses'} } ) {
        if ( !Cpanel::Validate::EmailCpanel::is_valid($email) ) {
            die Cpanel::Exception::create( 'AdminError', [ message => _locale()->mmaketext( "“[_1]” is not a valid email address.", $email ) ] );
        }
    }

    require Cpanel;
    require Cpanel::Mailman::ListManager;
    Cpanel::Mailman::ListManager::run_with_error_check(
        program => "$Cpanel::root/bin/manage_mailman_list_owner",
        args    => [ $full_list_name, $action, @{ $args->{'addresses'} } ],
    );

    return;
}

#Named arguments:
#   list_name
#   list_domain
#   addresses (array ref)
#
sub ADD_ADDRESSES_TO_LISTOWNER {
    my ( $self, %args ) = @_;

    return $self->_manage_listowner_addresses( 'add', \%args );
}

#Named arguments:
#   list_name
#   list_domain
#   addresses (array ref)
#
sub DELETE_ADDRESSES_FROM_LISTOWNER {
    my ( $self, %args ) = @_;

    return $self->_manage_listowner_addresses( 'delete', \%args );
}

#An optional array-ref argument "white-lists" certain list IDs for caching.
sub RECACHE_CONFIGURATION {
    my ( $self, $listids_ref ) = @_;

    $listids_ref ||= $self->_listlists();

    require Cpanel::Mailman::Config::Root;
    my $mailmanconfig_obj = Cpanel::Mailman::Config::Root->new( 'user' => $self->get_caller_username() );

    my ( $status, $statusmsg, $results_ref ) = $mailmanconfig_obj->recache_users_mailmanconfig($listids_ref);

    die $statusmsg if !$status;

    return $results_ref;
}

sub EXPORT_LISTS {
    my ($self)        = @_;
    my $user          = $self->get_caller_username();
    my $homedir       = $self->get_cpuser_homedir();
    my $export_dir    = "$homedir/mail/exported_lists/";
    my @mailing_lists = @{ $self->_listlists() };

    if ( !defined $mailing_lists[0] ) {
        die Cpanel::Exception::create( 'AdminError', [ message => _locale()->maketext('The system could not find a mailing list for this user.') ] );
    }

    Cpanel::AccessIds::do_as_user(
        $user,
        sub {
            Cpanel::Autodie::mkdir_if_not_exists( $export_dir, 0700 );
            return 1;
        }
    );

    foreach my $list (@mailing_lists) {
        my ( $list_name, $list_domain ) = $list =~ /(.*)_(.*)/;    # regex captures before and after the last underscore
        ( $list_name, $list_domain ) = $self->_verify_list_name_and_domain( $list_name, $list_domain );
        my $exported_file_path = "$export_dir$list_name.csv";
        my $export_cmd         = Cpanel::Mailman::Filesys::MAILMAN_DIR() . '/bin/list_members';
        my $output             = Cpanel::SafeRun::Simple::saferunallerrors( '/usr/local/cpanel/3rdparty/python/2.7/bin/python2', $export_cmd, '-f', $list );

        # Parse output and make it fit csv format
        # Current output reads 'Member Name <member.name@domain.com>', or just the email without brackets if there is no name
        my $content = ("email,name\n");
        my @members = split /\n/, $output;
        foreach my $member (@members) {
            if ( $member =~ /(.+) <(.+)>/ ) {
                $content .= "$2,\"$1\"\n";
            }
            elsif ( $member =~ /(.+)@.+/ ) {
                $content .= "$member,\"$1\"\n";
            }
            else {
                $content .= "\"$member\"\n";
            }
        }
        Cpanel::AccessIds::do_as_user(
            $user,
            sub {
                Cpanel::FileUtils::Write::overwrite( $exported_file_path, $content, 700 );
                return 1;
            }
        );
    }

    return 1;

}

#----------------------------------------------------------------------

sub _listlists {
    my ($self) = @_;

    require Cpanel::Mailman::Filesys;
    my ( $ok, $lists_ar ) = Cpanel::Mailman::Filesys::get_list_ids_for_domains( $self->get_cpuser_domains() );

    die $lists_ar if !$ok;

    return $lists_ar;
}

sub _MAILING_LISTS_DIR { require Cpanel::Mailman::Filesys; return Cpanel::Mailman::Filesys::MAILING_LISTS_DIR(); }

1;
