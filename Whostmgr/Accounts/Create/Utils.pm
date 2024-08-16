package Whostmgr::Accounts::Create::Utils;

# cpanel - Whostmgr/Accounts/Create/Utils.pm        Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Create::Utils

=head1 DESCRIPTION

This module exposes individually-testable bits of logic for account creation.
It’s not meant to be called outside L<Whostmgr::Accounts::Create>.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Autodie                      qw(mkdir_if_not_exists);
use Cpanel::Config::LoadCpConf           ();
use Cpanel::Context                      ();
use Cpanel::Email::Mailbox::Format       ();
use Cpanel::Email::Perms                 ();
use Cpanel::Email::Perms::User           ();
use Cpanel::Exception                    ();
use Cpanel::FileProtect::Constants       ();
use Cpanel::FileUtils::Write             ();
use Cpanel::LoadModule                   ();
use Cpanel::PasswdStrength::Check        ();
use Cpanel::PwCache                      ();
use Cpanel::Rand::Get                    ();
use Cpanel::SysAccounts                  ();
use Cpanel::Umask                        ();

use constant _EEXIST => 17;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $workloads_str = validate_child_workloads( \%ARGS )

Validates %ARGS’s C<child_workloads> (an array reference) against the
system configuration. Throws an exception if any of those are invalid.

Returns the string that should go into the cpuser file’s C<CHILD_WORKLOADS>
string.

=cut

sub validate_child_workloads ($args_hr) {
    my $workloads_str;

    my @bad;

    if ( $args_hr->{'child_workloads'} && @{ $args_hr->{'child_workloads'} } ) {
        my @workloads = @{ $args_hr->{'child_workloads'} };

        require Cpanel::LinkedNode::Worker::GetAll;
        my @valid = Cpanel::LinkedNode::Worker::GetAll::RECOGNIZED_WORKER_TYPES();

        require Cpanel::Set;

        require Cpanel::Server::Type::Profile;
        require Cpanel::Server::Type::Profile::Constants;

        my $profile = Cpanel::Server::Type::Profile::get_current_profile();

        if ( $profile ne Cpanel::Server::Type::Profile::Constants::STANDARD() ) {
            my $allowed = $Cpanel::Server::Type::Profile::Constants::PROFILE_CHILD_WORKLOADS{$profile};
            $allowed ||= [];

            @valid = Cpanel::Set::intersection(
                \@valid,
                $allowed,
            );
        }

        if ( my @bad = Cpanel::Set::difference( \@workloads, \@valid ) ) {
            die "Bad workload(s): @bad";
        }

        $workloads_str = join ',', @workloads;
    }

    return $workloads_str;
}

=head2 @workloads = parse_child_workloads( $WORKLOADS_STR )

Takes a string as C<validate_child_workloads()> returns and
returns a list of the workloads that that string contains.

=cut

sub parse_child_workloads ($workloads_str) {
    Cpanel::Context::must_be_list();
    return split m<,>, $workloads_str;
}

=head2 $password = get_password( %OPTS )

Given the C<%OPTS> hash from __createacct, returns either the
provided password (from C<password> or C<pass>) or, if not
provided, generates a new one attempting to meet the password
strength requirements.

This function should always return a nonempty string, but to
guard against future unforeseen bugs, it would be wise for the
caller to add an C<|| die>.

=cut

sub get_password (%OPTS) {
    my $password = $OPTS{'password'} || $OPTS{'pass'};
    if ( !$password ) {
        my $tries;
        $password = Cpanel::Rand::Get::getranddata(14);
        while ( !Cpanel::PasswdStrength::Check::check_password_strength( 'pw' => $password, 'app' => "createacct" ) && $tries++ < 20 ) {
            $password = Cpanel::Rand::Get::getranddata(14);
        }
    }
    return $password;
}

#----------------------------------------------------------------------

sub set_up_new_user_homedir {
    my ( $username, $domain, $mailbox_format, $hascgi ) = @_;    # TODO: refactor this to take a hash
    local ( $!, $^E );

    my ( $uuid, $ugid, $uhomedir ) = ( Cpanel::PwCache::getpwnam_noshadow($username) )[ 2, 3, 7 ];
    my $homedir_perms = Cpanel::SysAccounts::homedir_perms();

    try {
        Cpanel::Autodie::mkdir_if_not_exists( $uhomedir, $homedir_perms );
    }
    catch { warn $_->to_string() };

    _autodie_or_warn( 'Perms', 'chmod', $homedir_perms, $uhomedir );
    _autodie_or_warn( 'Perms', 'chown', $uuid, $ugid, $uhomedir );

    #Don’t ever touch the insides of the user’s home directory as root!
    #First we queue up the stuff to create, then we do it.

    $mailbox_format ||= Cpanel::Email::Mailbox::Format::get_mailbox_format_for_new_accounts();
    my @mail_dirs_to_create = Cpanel::Email::Mailbox::Format::get_relative_dirs_to_create($mailbox_format);

    # Try to get the permissions as close to what
    # we expect they will end up being so we do
    # not have to change them in a second pass
    # which can result in some unexpected conditions
    my @dirs_to_create = (

        #These stay 0700
        '.cpanel'           => 0700,
        '.cpanel/caches'    => 0700,
        '.cpanel/datastore' => 0700,

        #FileProtect will set these later to something
        #that may be a bit more open
        ".htpasswds"          => Cpanel::FileProtect::Constants::FILEPROTECT_OR_ACLS_DOCROOT_PERMS(),
        "public_html"         => Cpanel::FileProtect::Constants::FILEPROTECT_OR_ACLS_DOCROOT_PERMS(),
        "public_html/cgi-bin" => Cpanel::FileProtect::Constants::DEFAULT_DOCROOT_PERMS(),

        "tmp" => 0755,

        "public_ftp"          => 0750,
        "public_ftp/incoming" => 0700,    # They must turn this on in cPanel if they want to allow uploads (which is a bad idea)

        #Cpanel::Email::Perms will set permissions on these
        "etc"         => $Cpanel::Email::Perms::ETC_PERMS,
        "etc/$domain" => $Cpanel::Email::Perms::ETC_PERMS,

        "mail"         => $Cpanel::Email::Perms::MAILDIR_PERMS,
        "mail/$domain" => $Cpanel::Email::Perms::MAILDIR_PERMS,

        ( map { ( "mail/$_" => $Cpanel::Email::Perms::MAILDIR_PERMS ) } @mail_dirs_to_create ),
    );

    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            {
                my $umask = Cpanel::Umask->new(0);
                while ( my ( $dir, $mode ) = splice( @dirs_to_create, 0, 2 ) ) {
                    my $udir = "$uhomedir/$dir";
                    next if $udir eq "$uhomedir/public_html/cgi-bin" && $hascgi eq 'n';

                    if ( !mkdir( $udir, $mode ) ) {
                        if ( $! != _EEXIST ) {
                            warn Cpanel::Exception::create( 'IO::DirectoryCreateError', [ error => $!, path => $udir, mask => $mode ] );
                        }
                        else {
                            _autodie_or_warn( 'Perms', 'chmod', $mode, $udir );
                        }
                    }
                }

                my $format_path = Cpanel::Email::Mailbox::Format::get_mailbox_format_file_path($uhomedir);
                Cpanel::FileUtils::Write::overwrite( $format_path, $mailbox_format, 0640 );
            }
            _autodie_or_warn( 'File', 'symlink', "public_html", "$uhomedir/www" );

            copy_error_docs_to_docroot("$uhomedir/public_html");
        },
        $uuid,
        $ugid,
    );

    try {
        Cpanel::Email::Perms::User::ensure_all_perms($uhomedir);
    }
    catch {
        warn Cpanel::Exception::get_string($_);
    };

    return;
}

sub copy_error_docs_to_docroot {
    my ($docroot) = @_;

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    return if !$cpconf->{'copy_default_error_documents'};

    _copy_error_docs_to_docroot($docroot);

    return;
}

sub _copy_error_docs_to_docroot {
    my ($docroot) = @_;

    require Cpanel::Autodie::Dir;
    require Cpanel::FileUtils::Copy;

    my @error_docs = ('cp_errordocument.shtml');
    my $source_dir = '/usr/local/cpanel/htdocs';

    my $dh;
    Cpanel::Autodie::Dir::opendir( $dh, $source_dir );
    while ( my $file = readdir($dh) ) {
        next unless $file =~ /^\d{3}\.shtml$/;
        push @error_docs, $file;
    }
    Cpanel::Autodie::Dir::closedir($dh);

    return if !@error_docs;

    foreach my $doc (@error_docs) {
        next if -e "$docroot/$doc";
        next unless -e "${source_dir}/${doc}";
        Cpanel::FileUtils::Copy::safecopy( "/usr/local/cpanel/htdocs/$doc", "$docroot/$doc" );
    }

    return;
}

#----------------------------------------------------------------------

my %_func_cache;

sub _autodie_or_warn {
    my ( $module, $func_name, @args ) = @_;

    local $@;
    Cpanel::LoadModule::load_perl_module("Cpanel::Autodie::$module") if !$INC{"Cpanel/Autodie/$module.pm"};

    my $return;
    eval { $return = ( $_func_cache{$module}{$func_name} ||= "Cpanel::Autodie::$module"->can($func_name) )->(@args) };

    if ($@) {

        # $@ is not always a Cpanel::Exception
        # so use Cpanel::Exception::get_string as it
        # knows what to do
        warn Cpanel::Exception::get_string($@);
    }

    return $return;
}

1;
