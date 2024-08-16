package Cpanel::Backups;

# cpanel - Cpanel/Backups.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Carp ();

use Cpanel                  ();
use Cpanel::API             ();
use Cpanel::AdminBin        ();
use Cpanel::AdminBin::Call  ();
use Cpanel::DB              ();
use Cpanel::Email           ();
use Cpanel::Encoder::Tiny   ();
use Cpanel::Encoder::URI    ();
use Cpanel::Exception       ();
use Cpanel::LoadModule      ();
use Cpanel::Locale          ();
use Cpanel::Debug           ();
use Cpanel::PipeHandler     ();
use Cpanel::SafeDir         ();
use Cpanel::SafeRun::Object ();
use Cpanel::SafeRun::Simple ();
use Cpanel::ConfigFiles     ();
use Cpanel::Form            ();
use Cpanel::TempFile        ();
use Cpanel::Quota::Parse    ();

use Whostmgr::Backup::Pkgacct::Config ();

$Cpanel::Backups::VERSION = '2.0';

my $locale;

sub restorefiles {
    return if _notallowed("restore_files");

    my $dir =
      defined $Cpanel::FORM{'dir'}
      ? safedir( $Cpanel::FORM{'dir'} )
      : $Cpanel::abshomedir;

    my $html_safe_dir = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);

    chdir $dir or Carp::croak "Can not change into $html_safe_dir: $!";

  FILE:
    foreach my $file ( sort keys %Cpanel::FORM ) {
        local $Cpanel::IxHash::Modify = 'none';
        next FILE if $file !~ m/^file-(.*)/;

        my $origfile = $1;
        $Cpanel::FORM{$file} =~ s{\n}{}g;
        my @FTREE = split( /([\\\/])/, $origfile );
        my $fname = safefile( $FTREE[-1] );

        my $html_safe_output;
        foreach my $compression_opt ( '-z', '', '-j' ) {
            my $opts   = [ '-C', $Cpanel::abshomedir, '-x', '-v', $compression_opt, '-p', '-f', $Cpanel::FORM{$file} ];
            my $runner = Cpanel::SafeRun::Object->new(
                'program'      => 'tar',
                'args'         => $opts,
                'timeout'      => $Whostmgr::Backup::Pkgacct::Config::SESSION_TIMEOUT,
                'read_timeout' => $Whostmgr::Backup::Pkgacct::Config::READ_TIMEOUT,
            );

            $html_safe_output = Cpanel::Encoder::Tiny::safe_html_encode_str( $runner->stdout );
            print $html_safe_output;
            last if $runner->stderr eq '';    # stop if no errors are encountered
        }
    }

    Cpanel::Email::fix_pop_perms();

    return;
}

sub restoredb {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ($formref) = @_;
    return if _notallowed("restore_databases");

    alarm(7200);
    local $SIG{'PIPE'} = \&Cpanel::PipeHandler::pipeBGMgr;

    my $mysqlhost = Cpanel::AdminBin::adminrun( "cpmysql", 'GETHOST' );

    local $ENV{'REMOTE_MYSQL_HOST'} = $mysqlhost if $mysqlhost;

    if ( $ENV{'SESSION_TEMP_USER'} ) {

        # TODO: Create a UAPI function that seperates out this functionality
        # that will report errors.  This must remain here for legacy compat
        Cpanel::AdminBin::Call::call( 'Cpanel', 'session_call', 'SETUP_TEMP_SESSION', { 'session_temp_user' => $ENV{'SESSION_TEMP_USER'} } );
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::TempEnv');
    my $temp_mysql_env = eval { Cpanel::MysqlUtils::TempEnv->new(); };

    $locale ||= Cpanel::Locale->get_handle();

    if ( !$temp_mysql_env ) {
        return _backups_error( $locale->maketext( "The system could create temporary mysql environment because of an error: [_1].", Cpanel::Exception::get_string($@) ) );
    }

    my $dir =
      defined $Cpanel::FORM{'dir'}
      ? safedir( $Cpanel::FORM{'dir'} )
      : $Cpanel::abshomedir;

    chdir $dir or Carp::croak "Can not change into $dir: $!";

    my $files_ref = Cpanel::Form::get_uploaded_files_ar($formref);

    # if no files were successfully uploaded
    if ( not @$files_ref ) {
        if ( my @errors = Cpanel::Form::get_errors() ) {
            for my $error (@errors) {
                print "$error\n\n";
            }
        }
        else {
            print $locale->maketext("No files uploaded.") . "\n\n";
        }
        return;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlDumpParse');
  FILE:
    foreach my $file_data ( @{$files_ref} ) {
        my $file_path = $file_data->{'filename'};
        my $fname     = $file_data->{'formname'};

        my $db = ( split( m{/+}, $file_path ) )[-1];

        $db =~ s/(?:\.sql)?(?:\.gz)?$//;

        my ( $leading_data, $upload_fh );

        my $sf = Cpanel::TempFile->new( { path => qq{$Cpanel::abshomedir/tmp} } );

        my ( $sql_file, $sfh ) = $sf->file();
        close $sfh;
        if ( $file_path =~ m/\.gz$/i ) {
            my $tmp_file = Cpanel::Form::get_uploaded_file_temp_path( $fname, $formref );

            # test if this is a valid gz file using gzip directly; if not the process will exit 1; otherwise, decompress
            local $?;
            system qq{gzip -tv $tmp_file > /dev/null 2>&1 && gzip -dfc -S="tmp" $tmp_file > $sql_file 2>&1};
            my $status = $? >> 8;

            # handle error modes of the gzip decompression
            if ( $status != 0 or not -e $sql_file ) {

                # assumed failure mode
                my $error = $locale->maketext( qq{Failed to decompress “[_1]”. Make sure file is valid.}, $file_path );

                # check if we've put user's quota over or at limit
                my $quota = Cpanel::SafeRun::Simple::saferun( '/usr/local/cpanel/bin/quota', $Cpanel::user );
                my ( $used, $limit ) = Cpanel::Quota::Parse::parse_quota($quota);

                if ( $used >= $limit ) {
                    $error = $locale->maketext( qq{Decompressing “[_1]” has pushed “[_2]” over quota.}, $file_path, $Cpanel::user );
                }
                elsif ( not -e $sql_file ) {
                    $error = $locale->maketext( qq{Decompression failed for an unknown reason. “[_1]” doesn’t exist.}, $sql_file );
                }

                $error .= qq{\n\n} . $locale->maketext( qq{Decompression via [asis,gzip] exited during decompression with a status of “[_1]”.}, $status );
                Cpanel::Debug::log_warn($error);
                $Cpanel::CPERROR{$Cpanel::context} = $error;
                print $error;
                next FILE;
            }

            # get handle for the decompressed gz file, $sql_file
            open $upload_fh, q{<}, $sql_file or die $!;
        }
        else {
            # get handle for the uncompressed sql file
            $upload_fh = Cpanel::Form::open_uploaded_file( $fname, $formref );
        }

        # ensure the file handle has been set
        if ( !$upload_fh ) {
            my $error = "Failed to open uploaded file: $fname ($!)";
            Cpanel::Debug::log_warn($error);
            $Cpanel::CPERROR{$Cpanel::context} = $error;
            next FILE;
        }

        read( $upload_fh, $leading_data, 65535 );
        seek( $upload_fh, 0, 0 );

        # Transform invalid DEFINER clauses
        my $mysql_user    = $temp_mysql_env->get_mysql_user();
        my $definer_regex = Cpanel::MysqlDumpParse::get_definer_re();

        my $def_fh;
        my $def_pid;
        if ( $def_pid = open( $def_fh, '-|' ) ) {
            $upload_fh = $def_fh;
        }
        elsif ( defined $def_pid ) {
            select STDOUT;
            open( my $fh, '<&=' . fileno($upload_fh) );
            while ( my $line = <$fh> ) {
                $line =~ s/$definer_regex/DEFINER=`$mysql_user`\@$2/g;
                print $line;
            }
            close $fh;
            exit(0);
        }
        else {
            my $error = "Failed for fork() to transform script";
            Cpanel::Debug::log_warn($error);
            $Cpanel::CPERROR{$Cpanel::context} = $error;
            next FILE;
        }

        if ( $leading_data =~ /Database:\s(.*?)\r?\n/sig ) {
            print $locale->maketext("Determined database name from sql") . "\n\n";
            $db = $1;
        }
        chomp $db;
        $db =~ s/[\r\n\t\`\"\' ]//g;

        if ( !$db ) {
            Cpanel::Debug::log_warn("No database found in sql file $fname");
            $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'The file “[_1]” does not contain a database to restore.', $fname );
            next FILE;
        }

        print $locale->maketext( "Restoring database “[_1]”", Cpanel::Encoder::Tiny::safe_html_encode_str($db) ) . "\n\n";
        $db = Cpanel::DB::add_prefix_if_name_and_server_need($db);

        Cpanel::AdminBin::adminrun( 'cpmysql', 'ADDDB', $db );

        if ( my $mysql_pid = open( my $mysql_fh, '-|' ) ) {
            my $buffer;
            while ( read( $mysql_fh, $buffer, 65535 ) ) { }
            close($mysql_fh);
            waitpid( $mysql_pid, 0 );
            print $locale->maketext("Done!") . "\n\n";
        }
        elsif ( defined $mysql_pid ) {
            open( STDIN, '<&=' . fileno($upload_fh) );
            $temp_mysql_env->exec_mysql( '-v', $db );
            exit(1);
        }
        else {
            my $error = "Failed for fork() to execute mysql";
            Cpanel::Debug::log_warn($error);
            $Cpanel::CPERROR{$Cpanel::context} = $error;
            next FILE;
        }
        waitpid( $def_pid, 0 );
    }

    return;
}

sub restoreaf {
    return if _notallowed("restore_email_filters");

    my $dir =
      defined $Cpanel::FORM{'dir'}
      ? safedir( $Cpanel::FORM{'dir'} )
      : $Cpanel::abshomedir;

    chdir $dir or Carp::croak("Can not change into $dir: $!");

  FILE:
    foreach my $file ( sort keys %Cpanel::FORM ) {
        next FILE if ( $file =~ m/-key$/ || $file !~ m/^file-(.*)/ );
        local $Cpanel::IxHash::Modify = 'none';
        my $origfile = $1;
        $Cpanel::FORM{$file} =~ s{\n}{}g;
        my @FTREE = split( /([\\\/])/, $origfile );
        my $fname = safefile( $FTREE[-1] );

        my $at = $fname;
        $at =~ s/\.gz$//;

        $locale ||= Cpanel::Locale->get_handle();

        my $html_safe_at = Cpanel::Encoder::Tiny::safe_html_encode_str($at);

        if ( $at =~ /^aliases/ ) {
            $at =~ s/^aliases-//;

            if ( !_account_has_domain($at) ) {
                my $html_safe_domain = Cpanel::Encoder::Tiny::safe_html_encode_str($at);
                print $locale->maketext( 'The system failed to restore file “[_1]” because you do not own the domain “[_2]”.', $html_safe_at, $html_safe_domain );
                next;
            }

            # Make sure the /etc/vfilters files exist otherwise the
            # file will not be created
            Cpanel::AdminBin::adminrun( "mx", 'ENSUREEMAILDATABASESFORDOMAIN', $at );
            open( GZR, '-|' ) || exec( 'gzip', '-dc', $Cpanel::FORM{$file} );
            open my $vf_fh, '>', "$Cpanel::ConfigFiles::VALIASES_DIR/$at"
              or Carp::croak "$Cpanel::ConfigFiles::VALIASES_DIR/$html_safe_at open failed: $!";
            while (<GZR>) {
                print {$vf_fh} $_;
            }
            close GZR;
            close $vf_fh;

            print $locale->maketext('Successfully imported the backup.');
            next;
        }
        ## could be either a gzipped YAML file (metafilter.$user.gz), a YAML file gunzipped
        ##   presumably by the browser (filter.yaml), or the deprecated Exim format
        ##   (named by $domain, intended for /etc/vfilters, which may or may not have
        ##   the 'filter-' prefix on it
        else {
            my $fh_in;
            if ( $fname =~ m/\.gz$/ ) {
                open( $fh_in, '-|' ) || exec( 'gzip', '-dc', $Cpanel::FORM{$file} );
                $fname =~ s/\.gz$//;
            }
            else {
                open( $fh_in, '<', $Cpanel::FORM{$file} )
                  or Carp::croak "Failed to open uploaded file: $Cpanel::FORM{$file} ($!)";
            }

            my @_contents;
            while (<$fh_in>) {
                push( @_contents, $_ );
            }
            close $fh_in;
            my $contents = join( '', @_contents );

            Cpanel::LoadModule::load_perl_module('Cpanel::YAML::Syck');
            my $is_yaml = 0;
            eval {
                ## suppress error output while determining if is YAML
                local $SIG{'__DIE__'};
                YAML::Syck::Load($contents);
                $is_yaml = 1;
            };

            if ($is_yaml) {
                my $fn_yaml = "$Cpanel::homedir/.cpanel/filter.yaml";
                open( my $fh_out, '>', $fn_yaml ) or Carp::croak "$fn_yaml open failed: $!";
                print {$fh_out} $contents;
                close($fh_out);

                Cpanel::LoadModule::load_perl_module('Cpanel::Email::Filter');
                ## handles the transition from internal data structure to /etc/vfilters
                my $fstore = Cpanel::Email::Filter::_fetchfilter($fn_yaml);

                # Do some minor validation before creating the necessary files and folders
                if ( !( $fstore->{'filter'} && scalar @{ $fstore->{'filter'} } ) ) {
                    print $locale->maketext('Error: The uploaded file did not contain any filters.');
                    next;
                }

                # Make sure the /etc/vfilter files exist otherwise
                # the filters will not be put into /etc/vfilters by _store_exim_filter
                Cpanel::AdminBin::adminrun( "mx", 'ENSUREEMAILDATABASES', $Cpanel::CPDATA{'DNS'} );

                ## sending an $account of undef means _store_exim_filter stores the
                ##   Exim filters in each of $Cpanel::user's @Cpanel::DOMAINS
                my ( $ok, $message ) = Cpanel::Email::Filter::_store_exim_filter( undef, $fstore );
                if ($ok) {
                    print $locale->maketext('Successfully imported the backup.');
                }
                else {
                    print $message;
                }
                next;
            }
            elsif ( $fname =~ s/^filter-// ) {    ## $fname might be '^filter-${domain}

                next if !_account_has_domain($fname);

                my $fn_exim = "$Cpanel::ConfigFiles::VFILTERS_DIR/$fname";

                # Make sure the /etc/vfilters files exist otherwise the
                # file will not be created
                Cpanel::AdminBin::adminrun( "mx", 'ENSUREEMAILDATABASES', $Cpanel::CPDATA{'DNS'} );

                open( my $fh_out, '>', $fn_exim ) or Carp::croak "$fn_exim open failed: $!";
                print {$fh_out} $contents;
                close $fh_out;
                print $locale->maketext('Successfully imported the backup.');
                next;
            }
            else {
                print $locale->maketext('The system failed to restore file because of an unrecognized format. Email forwarder file names must start with “aliases-”. Email filter files must either be a [asis,YAML] file, or they must start with “filter-” and use the [asis,Exim] filter format.');
                next;
            }
        }
    }
    return;
}

sub _account_has_domain {
    my ($domain) = @_;

    return 1 if grep( /^\Q$domain\E$/i, @Cpanel::DOMAINS );
    return 0;
}

sub restorefile {
    return if _notallowed(1);

    my $file           = safefile( shift() );
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    my $locale = Cpanel::Locale->get_handle();
    my ( $newtrash, $oldloc );
    chdir "$Cpanel::abshomedir/.trash"
      or Carp::croak "Could not chdir into trash: $!";

    open my $res_fh, '<', '.trash_restore'
      or Carp::croak( $locale->maketext_plain_context('[output,strong,Error]: The system was not able to find the trash index file.') );
    while (<$res_fh>) {
        if (/^\Q${file}\E=/) {
            ( undef, $oldloc ) = split( /=/, $_, 2 );
            $oldloc =~ s/\n//g;
            rename "$file", "$oldloc";
        }
        else {
            $newtrash = $newtrash . $_;
        }
    }
    close $res_fh;

    if ( $oldloc eq '' ) {
        Carp::croak "Trash restore file failed: Could not lookup $html_safe_file in the .trash_restore database.";
    }

    my $html_safe_oldloc = Cpanel::Encoder::Tiny::safe_html_encode_str($oldloc);
    open my $wres_fh, '>', '.trash_restore'
      or Carp::croak "Updating Trash restore file failed: $!";
    print {$wres_fh} $newtrash;
    close $wres_fh;
    return $locale->maketext( 'Restored “[_1]” to “[_2]”.', $html_safe_file, $html_safe_oldloc );
}

sub fullbackup {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $dest, $server, $user, $pass, $email, $port, $rdir, $sshkey_name, $sshkey_passphrase ) = @_;
    return if _notallowed();

    require Cpanel::StringFunc::Trim;
    $dest   =~ s/\s//g;
    $server =~ s/\s//g if length $server;
    Cpanel::StringFunc::Trim::ws_trim( \$user );    ## user can have a space in the middle for some remote ftp servers
    $port =~ s/\s//g if length $port;
    $dest ||= 'homedir';

    my %api_map = (
        'homedir'      => [ 'fullbackup_to_homedir',           {} ],
        'passiveftp'   => [ 'fullbackup_to_ftp',               { 'variant' => 'passive' } ],
        'ftp'          => [ 'fullbackup_to_ftp',               { 'variant' => 'active' } ],
        'scp'          => [ 'fullbackup_to_scp_with_password', {} ],
        'scp_with_key' => [ 'fullbackup_to_scp_with_key',      {} ],
    );

    if ( $dest eq 'scp' && $sshkey_name ) {
        $dest = 'scp_with_key';
    }

    if ( !$api_map{$dest} ) {
        die "The “$dest” destination is not supported.";
    }

    my $result = Cpanel::API::wrap_deprecated(
        "Backup",
        $api_map{$dest}->[0],
        {
            host             => $server,
            username         => $user,
            password         => $pass,
            email            => $email,
            port             => $port,
            directory        => $rdir,
            'key_name'       => $sshkey_name,
            'key_passphrase' => $sshkey_passphrase,
            %{ $api_map{$dest}->[1] }
        }
    );

    if ( $Cpanel::CPERROR{'backup'} ) {
        $Cpanel::CPERROR{'backups'} = $Cpanel::CPERROR{'backup'};
    }
    my $message = $result->status() ? $result->data() : $result->errors_as_string();
    print "$message\n";
    return ( $result->status(), $message );
}

sub listfullbackups {
    return if _notallowed("list_backups");    #  nothing in original

    my $bcklistref = _fetchfullbackups();
    if (@$bcklistref) {
        foreach my $bck_ref (@$bcklistref) {
            my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str( $bck_ref->{'file'} );
            my $uri_safe_file  = Cpanel::Encoder::URI::uri_encode_str( $bck_ref->{'file'} );
            if ( $bck_ref->{'status'} eq 'complete' ) {
                print qq(<div class="okmsg"><b><a href="$ENV{'cp_security_token'}/download?file=$uri_safe_file">$html_safe_file</a></b> ($bck_ref->{'localtime'})<br /></div>\n);
            }
            elsif ( $bck_ref->{'status'} eq 'inprogress' ) {
                print qq(<div class="warningmsg">$html_safe_file ($bck_ref->{'localtime'}) [in progress]<br /></div>\n);
            }
            else {
                print qq(<div class="errormsg">$html_safe_file ($bck_ref->{'localtime'}) [failed, timeout]<br /></div>\n);
            }

        }
    }
    else {
        print "No Previous Backups<br />\n";
    }
    return;
}

sub api2_listfullbackups {
    return _fetchfullbackups();
}

sub _fetchfullbackups {
    my $now = time();

    Cpanel::LoadModule::lazy_load_module('HTTP::Date');

    opendir my $home_dh, $Cpanel::abshomedir
      or Carp::croak "homedir read failed: $!";
    my @FILES = readdir $home_dh;
    closedir $home_dh;

    my @RSD;
    my $backup_count = 0;
    foreach (@FILES) {
        if (/^(backup-\d+\.\d+\.\d+_\d+\-\d+\-\d+_$Cpanel::user)(.tar(?:.gz)?)$/) {
            $backup_count++;
            my $filename = $1;
            my $suffix   = $2;
            my $status   = 'complete';
            if ( -e "$Cpanel::abshomedir/$filename" ) {
                my $starttime = 0;
                if ( -f "$Cpanel::abshomedir/$filename" ) {
                    open( my $tmp_fh, '<', $Cpanel::abshomedir . '/' . $filename );
                    my $st = readline($tmp_fh);
                    close($tmp_fh);
                    if ( $st =~ /\S+\s+(\d+)/ ) {
                        $starttime = $1;
                    }
                }
                $status = ( ( $starttime + 10000 ) < $now ) ? 'timeout' : 'inprogress';
            }

            $filename =~ /^backup-(\d+)\.(\d+)\.(\d+)_(\d+)\-(\d+)\-(\d+)/;
            my $time_str  = sprintf( "%04d-%02d-%02d %02d:%02d:%02d", $3, $1, $2, $4, $5, $6 );
            my $time_t    = HTTP::Date::str2time($time_str);
            my $localtime = localtime($time_t);

            push @RSD, { 'file' => $filename . $suffix, 'status' => $status, 'time' => $time_t, 'localtime' => $localtime };
        }
    }

    @RSD = sort { $a->{'time'} <=> $b->{'time'} } @RSD;

    return \@RSD;
}

sub safedir {
    goto &Cpanel::SafeDir::safedir;
}

sub safefile {
    my $file = shift;
    while ( $file =~ /\// ) {
        $file =~ s/[\/<>;]//g;    # TODO: same as trunk/ -r 3556 ???
    }
    return $file;
}

# Tested directly
# NOTE: This method wires into the the requirements checks that UAPI uses for the equivalent functionality
#       to determine access using features, roles, and demo mode.
sub _notallowed {

    my ($uapi_equivalent) = @_;

    require Cpanel::API::Backup;

    my $role    = $Cpanel::API::Backup::API{_needs_role};
    my $feature = $Cpanel::API::Backup::API{_needs_feature};

    my $api_hr = $uapi_equivalent && $Cpanel::API::Backup::API{$uapi_equivalent} ? $Cpanel::API::Backup::API{$uapi_equivalent} : { needs_feature => 'backup', allow_demo => 0 };

    $role    ||= $api_hr->{needs_role};
    $feature ||= $api_hr->{needs_feature};

    my $demo = $api_hr->{allow_demo} || 0;

    if ( $role || $feature || !$demo ) {

        my $verify = {};
        @{$verify}{qw(needs_role needs_feature allow_demo)} = ( $role, $feature, $demo );

        require Cpanel::Security::Authz;

        local $@;
        if ( !eval { Cpanel::Security::Authz::verify_user_meets_requirements( $Cpanel::user, $verify ); 1; } ) {
            print Cpanel::Exception::get_string_no_id($@);
            return 1;
        }

    }

    return 0;
}

our %API = (
    listfullbackups => { allow_demo => 1 },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub _backups_error {
    my ($err) = @_;
    $Cpanel::CPERROR{$Cpanel::context} = "$err\n";
    Cpanel::Debug::log_warn($err);
    print Cpanel::Encoder::Tiny::safe_html_encode_str("$err\n");

    return ( 0, $Cpanel::CPERROR{$Cpanel::context} );
}

1;
