package Cpanel::cPAddons::Util;

# cpanel - Cpanel/cPAddons/Util.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Helper functions that are not instance methods and do not take
# an instance of Cpanel::cPAddons::Obj as an argument can go here
# to be shared by more than one Cpanel::cPAddons::* module.

use strict;

use Cpanel::Config::LoadCpConf    ();
use Cpanel::DB::Prefix            ();
use Cpanel::Encoder::Tiny         ();
use Cpanel::Hostname              ();
use Cpanel::LoadModule            ();
use Cpanel::PasswdStrength::Check ();
use Cpanel::SV                    ();

use Cpanel::Imports;

# Constants
our $MAX_GENERATE_RANDOM_TIMES = 10_000;
our $MYSQL_PASSWORD_LENGTH     = 12;
our $GENERATED_USERNAME_LENGTH = 10;
our $GENERATED_PASSWORD_LENGTH = 12;

=head1 NAME

Cpanel::cPAddons::Util

=head1 DESCRIPTION

Smaller cPAddons utility functions that do not take an $obj argument.

=head1 FUNCTIONS

=head2 must_not_be_root(REASON)

Dies with REASON as the message if running as root. This is meant as a safety net to prevent
symlink attacks, but the protection should never be invoked under normal circumstances.

=cut

sub must_not_be_root {
    my ($reason) = @_;
    if ( $> == 0 ) {
        if ($reason) {
            _confess( 'This function was called as root, which is not safe: ' . $reason );
        }
        _confess('This function was called as root, which is not safe.');
    }
    return 1;
}

=head2 get_no_modified_cpanel_addons_setting()

Returns the state of the B<cpaddons_no_modified_cpanel> tweak setting.

=cut

sub get_no_modified_cpanel_addons_setting {
    my $cpconf_ref = %Cpanel::CONF ? \%Cpanel::CONF : Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    return exists $cpconf_ref->{'cpaddons_no_modified_cpanel'} && $cpconf_ref->{'cpaddons_no_modified_cpanel'} ne ''
      ? $cpconf_ref->{'cpaddons_no_modified_cpanel'}
      : 0;
}

=head2 get_no_3rd_party_addons_setting()

Returns the state of the B<cpaddons_no_3rd_party> tweak setting.

=cut

sub get_no_3rd_party_addons_setting {
    my $cpconf_ref = %Cpanel::CONF ? \%Cpanel::CONF : Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    my $no_3rd_party =
      exists $cpconf_ref->{'cpaddons_no_3rd_party'} && $cpconf_ref->{'cpaddons_no_3rd_party'} ne ''
      ? $cpconf_ref->{'cpaddons_no_3rd_party'}
      : 0;
    return $no_3rd_party;
}

=head2 check_max_subdomains()

For the current user, returns information about whether we have reached the subdomain limit.

If the limit has been reached:

  Returns (1, count)

Otherwise:

  Returns (0, count)

=cut

sub check_max_subdomains {
    my $count = 0;
    if ( !exists $Cpanel::CPDATA{'MAXSUB'} || $Cpanel::CPDATA{'MAXSUB'} =~ /unlimited/i || $Cpanel::CPDATA{'MAXSQL'} eq '' ) {
        if (wantarray) {
            require Cpanel::SubDomain;
            $count = Cpanel::SubDomain::countsubdomains();
            return ( 1, $count );
        }
        else {
            return 1;
        }
    }
    else {
        require Cpanel::SubDomain;
        $count = Cpanel::SubDomain::countsubdomains();
        if ( $count < $Cpanel::CPDATA{'MAXSUB'} ) {
            return wantarray ? ( 1, $count ) : 1;
        }
        else {
            return wantarray ? ( 0, $count ) : 0;
        }
    }
}

=head2 checkmaxdbs()

For the current user, returns information about whether we have reached the database limit.

If the limit has been reached:

  Returns (1, count)

Otherwise:

  Returns (0, count)

=cut

sub checkmaxdbs {
    my $dbc;
    return 1
      if !wantarray
      && ( $Cpanel::CPDATA{'MAXSQL'} =~ /unlimited/i || $Cpanel::CPDATA{'MAXSQL'} eq '' );
    if ( $Cpanel::CPCACHE{'mysql'}{'cached'} ) {
        $dbc =
          ref $Cpanel::CPCACHE{'mysql'}{'DB'} eq 'HASH'
          ? keys %{ $Cpanel::CPCACHE{'mysql'}{'DB'} }
          : 0;
    }
    else {

        # this only counts the user's DBs
        $dbc = int(`/usr/local/cpanel/bin/cpmysqlwrap COUNTDBS`);    #safesecure2
    }
    return ( 1, $dbc )
      if $Cpanel::CPDATA{'MAXSQL'} =~ /unlimited/i || $Cpanel::CPDATA{'MAXSQL'} eq '';
    return wantarray ? ( 0, $dbc ) : 0 if $dbc >= $Cpanel::CPDATA{'MAXSQL'};
    return wantarray ? ( 1, $dbc ) : 1;
}

=head2 find_unused_name(USERNAME, NAME, EXISTS_CR, MAXLENGTH)

Finds an unused name for the database.

This does not use Cpanel::DB's functions for adding DB prefixes. Even if DB prefixing is
disabled, we always want to use a prefix here.

=head3 Arguments

- USERNAME - String - The current user, which is used for creating the DB prefix

- NAME - String - The base name of the database

- EXISTS - Code ref - Checks whether the database exists

- MAXLENGTH - Number - If this total name length is reached while trying to find an unused name,
give up. (Throws an exception in this case)

=head3 Returns

The database name to use

=cut

sub find_unused_name {
    my ( $username, $name, $exists, $maxlength ) = @_;

    my $prefix = Cpanel::DB::Prefix::username_to_prefix($username);

    my $count = 0;
    my $use_this_name;
    while ( $count < $MAX_GENERATE_RANDOM_TIMES ) {    #sanity
        my $try_this_name = $prefix . '_' . $name . ( $count || q{} );

        #This should be very, very, very rare.
        last if length($try_this_name) > $maxlength;

        if ( !$exists->($try_this_name) ) {
            $use_this_name = $try_this_name;
            last;
        }

        $count++;
    }

    #Again, this should be exceptionally rare. Knock on wood.
    if ( !length $use_this_name ) {
        die locale()->maketext( 'The system could not generate an unused name based on the prefix “[_1]” and the suffix “[_2]” after [quant,_3,attempt,attempts].', $prefix, $name, $MAX_GENERATE_RANDOM_TIMES );
    }

    return $use_this_name;
}

sub _does_db_exist {
    my ($db) = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin');
    return Cpanel::AdminBin::adminrun( 'cpmysql', 'DBEXISTS', $db );
}

sub _does_dbuser_exist {
    my ($db) = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin');
    return Cpanel::AdminBin::adminrun( 'cpmysql', 'USEREXISTS', $db );
}

sub _droptables {
    my ( $db, $pfx, $usr, $pss, $hst ) = @_;

    my $just_made = _create_my_cnf_if_needed( $usr, $pss, $hst ) || '';

    require Cpanel::DbUtils;
    Cpanel::LoadModule::load_perl_module('IPC::Open3');
    my %tbls;
    IPC::Open3::open3( \*MYSQL, \*MYRES, ">&STDERR", Cpanel::DbUtils::find_mysql(), '--defaults-file=' . $just_made, $db );
    print MYSQL 'SHOW TABLES\G';
    close MYSQL;

    while (<MYRES>) {
        chomp();
        next unless m/Tables\_in\_/;
        my ($tbl) = $_ =~ m/^Tables\_in\_\Q$db\E\:\s+(\w+)/;
        if ( defined($tbl) && $tbl =~ m/^\Q$pfx\E\_/ ) {
            $tbls{$tbl}++;
        }
    }
    close MYRES;
    if (%tbls) {
        my $sql_data = 'DROP TABLE ' . join( ', ', sort keys %tbls ) . ";\n";
        IPC::Open3::open3( \*MYSQL, \*MYRES, ">&STDERR", Cpanel::DbUtils::find_mysql(), '--defaults-file=' . $just_made, $db );
        print MYSQL $sql_data;
        close MYSQL;

        # Case 83157: Consume the data so that the program actually completes.
        while (<MYRES>) { }
        close MYRES;
    }

    unlink $just_made;

    return 1;
}

sub remove_install_directory {
    my ( $dir, $info_hr, $version ) = @_;
    $dir =~ s/\.\.//g;
    $dir =~ s/^\///;
    $version = $info_hr->{'version'} if !$version;

    require Cpanel::cPAddons::Notices;
    my $notices = Cpanel::cPAddons::Notices::singleton();

    if ( $dir eq './' ) {

        my $files_and_folders = $info_hr->{$version} || $info_hr->{all_versions};

        # Installed in root, we must rely on list of packaged files and directories
        if ( $files_and_folders && ref $files_and_folders->{'public_html_install_files'} eq 'ARRAY' ) {
            for my $file ( @{ $files_and_folders->{'public_html_install_files'} } ) {
                if ( !_unlink($file) ) {
                    $notices->add_warning(
                        locale()->maketext(
                            'The system could not remove the “[_1]” file: [_2]',
                            Cpanel::Encoder::Tiny::safe_html_encode_str($file),
                            Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                        )
                    );
                }
            }
        }

        if ( $files_and_folders && ref $files_and_folders->{'public_html_install_dirs'} eq 'ARRAY' ) {
            for my $folder ( @{ $files_and_folders->{'public_html_install_dirs'} } ) {
                if ( !_rmdir($folder) ) {
                    $notices->add_warning(
                        locale()->maketext(
                            'The system could not remove the “[_1]” directory: [_2]',
                            Cpanel::Encoder::Tiny::safe_html_encode_str($folder),
                            Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                        )
                    );
                }
            }
        }

        if ( $files_and_folders && ref $files_and_folders->{'public_html_install_unknown'} eq 'ARRAY' ) {
            for my $rel_path ( @{ $files_and_folders->{'public_html_install_unknown'} } ) {
                my $exit = _rm_rf($rel_path);
                if ( $exit >> 8 != 0 || $? == -1 ) {
                    $notices->add_warning(
                        locale()->maketext(
                            'The system could not remove “[_1]” file(s) or folder(s), : [_2]',
                            Cpanel::Encoder::Tiny::safe_html_encode_str($rel_path),
                            Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                        )
                    );
                }
            }
        }

        return 1;
    }
    else {
        my ($dir_ut) = $dir =~ m{ (.*) }xms;
        return 0 if !$dir_ut;

        Cpanel::LoadModule::lazy_load_module('File::Copy::Recursive');
        if ( File::Copy::Recursive::pathrmdir("./$dir_ut") ) {    # FCR is used in FileUtils.pm
            my @rmpath = split /\//, $dir_ut;
            pop @rmpath;
            while (@rmpath) {
                _rmdir( join '/', @rmpath );                      # no warn/die because if the sub directories are not empty we don't want them removed :)
                pop @rmpath;
            }
            return 1;
        }
        else {
            return 0;
        }
    }
}

sub _rm_rf {
    my @list = _glob(shift);
    return _system( "/bin/rm", "-rf", "--", @list );
}

sub _glob {
    my @list = glob shift;
    return @list;
}

sub _unlink {
    my @args = @_;
    return unlink(@args);
}

sub _rmdir {
    my ($dir) = @_;
    return rmdir($dir);    # Don't pass an array to the builtin rmdir. It forces its argument into scalar context.
}

sub _system {
    my @args = @_;

    # We must load the module first so that the variable doesn't get overridden.
    require Cpanel::SafeRun::API;
    local $Cpanel::Parser::Vars::trap_defaultfh = 1;
    return Cpanel::SafeRun::API::html_encoded_api_safe_system(@args);
}

sub _get_patch_dry_run_flag {
    my $flag = '--dry-run';    # safe default

    Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Dynamic');
    Cpanel::SafeRun::Dynamic::livesaferun(
        'prog'      => [qw(patch --help)],
        'formatter' => sub {
            my ( $line, $quit_saferun_loop_sr ) = @_;
            if ( $line =~ /\-\-check/ ) {
                $flag = '--check';
                ${$quit_saferun_loop_sr} = 1;
            }
            return '';    # it gets printed.... yikes...
        },
    );

    return $flag;
}

sub _untaint {
    my $untainted = Cpanel::SV::untaint( $_[0] );
    $untainted =~ s/[`|;]//g;
    return $untainted;
}

sub _there_are_missing_whm_addons {
    my ( $info_hr, $obj ) = @_;
    my $need = 0;
    my $have = 0;

    if ( defined $info_hr->{'whm_addon'} && ref $info_hr->{'whm_addon'} eq 'ARRAY' ) {
        foreach my $addon_name ( @{ $info_hr->{'whm_addon'} } ) {
            next if !$addon_name;
            $need++;
            $have++ if _whm_addon_is_installed( $addon_name, $obj );
        }
    }
    return $need == $have ? 0 : 1;
}

sub _whm_addon_is_installed {
    my ( $addon_name, $obj ) = @_;

    if ( !-e '/var/cpanel/addonmodules' ) {
        $obj->add_critical_error(
            locale()->maketext(
                'No [asis,cPAddons] installed. The system could locate not the required [asis,cPAddon]: [_1]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($addon_name),
            )
        );
        return;
    }

    if ( open my $aol_fh, '<', '/var/cpanel/addonmodules' ) {
        my %installed;
        while (<$aol_fh>) {
            chomp;
            $installed{$_}++;
        }
        close $aol_fh;

        $obj->add_critical_error(
            locale()->maketext(
                'The system could locate not the required [asis,cPAddon]: [_1]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($addon_name),
            )
        ) if !exists $installed{$addon_name};

        return 1 if exists $installed{$addon_name};
        return 0;
    }
    else {
        $obj->add_critical_error(
            locale()->maketext(
                'The system could not read the installed Site Software package list: [_1]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($!),
            )
        );
    }

    return;
}

sub _create_my_cnf_if_needed {
    my ( $usr, $pss, $hst ) = @_;

    if ( !$usr || !$pss ) {
        logger()->warn('User or password not provided.');
        require Cpanel::cPAddons::Notices;
        Cpanel::cPAddons::Notices::singleton()->add_error( locale()->maketext('You did not provide the username or password.') );
        return;
    }

    require Cpanel::SafeRun::Errors;
    $hst = Cpanel::SafeRun::Errors::saferunnoerror( '/usr/local/cpanel/bin/cpmysqlwrap', 'GETHOST' ) if !$hst;
    $usr =~ s/\"/\\\"/g;
    $pss =~ s/\"/\\\"/g;

    if ( $> == 0 ) {
        if ( my $pid = fork() ) {
            waitpid( $pid, 0 );
        }
        else {
            Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::SetUids');
            Cpanel::AccessIds::SetUids::setuids($Cpanel::user);
            $usr = _untaint($usr);
            $pss = _untaint($pss);
            $hst = _untaint($hst);

            require Cpanel::Rand;
            my $file = Cpanel::Rand::gettmpfile();    # audit case 46806 ok
            $file = _untaint($file);
            return $file if _write_my_cnf( $file, $usr, $pss, $hst );
        }
    }
    else {
        require Cpanel::Rand;
        my $file = Cpanel::Rand::gettmpfile();    # audit case 46806 ok
        $file = _untaint($file);
        return $file if _write_my_cnf( $file, $usr, $pss, $hst );
    }
    return;
}

sub _write_my_cnf {
    my ( $file, $usr, $pss, $hst ) = @_;

    # untainting after setuids() call does not keep it untained here
    $file = _untaint($file);
    $usr  = _untaint($usr);
    $pss  = _untaint($pss);
    $hst  = _untaint($hst);

    require Fcntl;

    if ( sysopen( my $my_cnf, $file, Fcntl::O_WRONLY() | Fcntl::O_TRUNC() | Fcntl::O_CREAT(), 0640 ) ) {
        chmod 0640, $file;
        print {$my_cnf} qq([client]\nuser="$usr"\npassword="$pss"\nhost="$hst");
        close $my_cnf or return;
    }
    else {
        my $exception = $!;
        logger()->warn("Unable to create SQL configuration file, $file, with the error: $exception");
        require Cpanel::cPAddons::Notices;
        Cpanel::cPAddons::Notices::singleton()->add_error(
            locale()->maketext(
                'The system could not create the “[_1]” [asis,SQL] configuration file: [_2]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($file),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
            )
        );
        return;
    }

    return 1;
}

sub _get_user_from_path {
    my ($file) = @_;

    $file =~ s</{2,}></>g;    # deduplicate slashes to avoid empty pieces after split
    my @pieces = split /\//, $file;

    for my $idx ( 0 .. $#pieces ) {
        if ( $pieces[$idx] eq '.cpaddons' ) {
            return if $idx < 2;
            return $pieces[ $idx - 1 ];
        }
    }

    return;
}

sub _cleanse_input_hr {
    my ($input_hr) = @_;
    my %safe_input_hr =
      map { Cpanel::Encoder::Tiny::safe_html_encode_str($_) => Cpanel::Encoder::Tiny::safe_html_encode_str( $input_hr->{$_} ) }
      keys %$input_hr;
    return \%safe_input_hr;
}

sub admin_contact_email {
    my ($cpconf_ref) = @_;
    my $admincontactemail =
      exists $cpconf_ref->{'cpaddons_adminemail'} && $cpconf_ref->{'cpaddons_adminemail'}
      ? $cpconf_ref->{'cpaddons_adminemail'}
      : 'cPanel@' . Cpanel::Hostname::gethostname();
    return $admincontactemail;
}

sub generate_mysql_password {
    require Cpanel::PasswdStrength::Generate;
    for ( 1 .. $MAX_GENERATE_RANDOM_TIMES ) {

        #This password may go into a client defaults file (e.g., .my.cnf), the
        #encoder or parser for which may or may not be buggy w/r/t quotes and
        #hashes in values. So let's reject anything that has them.
        my $pw = Cpanel::PasswdStrength::Generate::generate_password(
            $MYSQL_PASSWORD_LENGTH,
            no_othersymbols => 1,    # Prevent #"'; from being included.
            no_symbols      => 1,    # Prevent symbols
        );

        if ( Cpanel::PasswdStrength::Check::check_password_strength( app => 'mysql', pw => $pw ) ) {
            return $pw;
        }
    }

    my $min_pw_strength = Cpanel::PasswdStrength::Check::get_required_strength('mysql');
    die locale()->maketext(
        'The system could not generate a [asis,MySQL] password that meets the minimum strength of [numf,_1] after [quant,_2,attempt,attempts].',
        $min_pw_strength,
        $MAX_GENERATE_RANDOM_TIMES
    );
}

sub generate_random_password {
    require Cpanel::PasswdStrength::Generate;
    for ( 1 .. $MAX_GENERATE_RANDOM_TIMES ) {

        my $pw = Cpanel::PasswdStrength::Generate::generate_password(
            $GENERATED_PASSWORD_LENGTH,
            no_othersymbols => 1,    # Prevent #"'; from being included. Double and single quote are known not to work with WordPress.
        );

        if ( Cpanel::PasswdStrength::Check::check_password_strength( app => 'addon', pw => $pw ) ) {
            return $pw;
        }
    }

    my $min_pw_strength = Cpanel::PasswdStrength::Check::get_required_strength('addon');
    die locale()->maketext(
        'The system could not generate a random [asis,cPAddon] password that meets the minimum strength of [numf,_1] after [quant,_2,attempt,attempts].',
        $min_pw_strength,
        $MAX_GENERATE_RANDOM_TIMES
    );
}

sub generate_random_username {
    require Cpanel::PasswdStrength::Generate;
    for ( 1 .. $MAX_GENERATE_RANDOM_TIMES ) {

        my $username = Cpanel::PasswdStrength::Generate::generate_password(
            $GENERATED_USERNAME_LENGTH,
            no_othersymbols => 1,    # Prevent #"' from being included.
            no_symbols      => 1,    # Prevent symbols
        );

        return $username if $username !~ m/^\d/;    # Prevent it starting with a digit
    }

    die locale()->maketext(
        'The system could not generate a random username after [quant,_1,attempt,attempts].',
        $MAX_GENERATE_RANDOM_TIMES
    );
}

=head2 unique_instance_id( instance => ..., create_time => ... )

Generate a unique id for a deployed instance of a cPAddon. This is used by UAPI for referencing instances
to manipulate. While instance names can be reused over time, unique instance ids will never be reused.

While the process of building the id itself is quite simple, you should use this function because
it provides a centralized facility to update the id format in the future.

=head3 Arguments

instance - String - The instance name (as seen in the instance YAML filename), which is the module name and a numeric suffix.

create_time - String - Seconds since unix epoch when the instance was initially deployed. This is used to distinguish between two instances
that might share the same instance name when one is deleted and the number gets reused.

=head3 Returns

A unique identifier for the instance

=cut

sub unique_instance_id {
    my %args = @_;
    my ( $instance, $create_time ) = delete @args{qw(instance create_time)};
    _confess('Unexpected arguments given to unique_instance_id()') if %args;

    if ( !_validate_instance($instance) ) {
        _confess( sprintf 'Invalid instance name “%s” given to unique_instance_id()', $instance );
    }
    if ( !_validate_timestamp($create_time) ) {
        _confess( sprintf 'Invalid timestamp “%s” given to unique_instance_id()', $create_time );
    }

    return join '.', $instance, $create_time;
}

sub _validate_instance {
    my ($instance) = @_;
    if ( ( $instance || '' ) =~ /^[^:]+::[^:]+::[^:]+\.[0-9]+$/ ) {
        return 1;
    }
    return 0;
}

sub _validate_timestamp {
    my ($timestamp) = @_;
    if ( ( $timestamp || '' ) =~ /^[0-9]{10}$/ ) {
        return 1;
    }
    return 0;
}

sub generate_unused_install_dir {
    my ( $base_path, $module_data ) = @_;

    my $install_dir = $module_data->{meta}{installdir} || '';
    my $path        = "$base_path/$install_dir";
    return $install_dir if !-d $path;
    for ( 1 .. $MAX_GENERATE_RANDOM_TIMES ) {
        return "$install_dir$_" if !-d "$path$_";
    }

    die locale()->maketext(
        'The system could not generate a valid install path for “[_1]” after [quant,_1, attempt, attempts].',
        Cpanel::Encoder::Tiny::safe_html_encode_str( $module_data->{app_name} ),
        $MAX_GENERATE_RANDOM_TIMES
    );
}

sub _confess {

    # Defer loading carp since we do not want to perlcc it in since we only call it on error
    Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
    die Cpanel::Carp::safe_longmess(@_);
}

1;
