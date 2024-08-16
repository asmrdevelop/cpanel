package Cpanel::ClamScanner;

# cpanel - Cpanel/ClamScanner.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#-------------------------------------------------------------------------------
# NOTE:
# This module is expected to have 2 identical copies:
#     - $DS/cpanel/trunk/Cpanel/ClamScanner.pm
#           [This is kept as the master copy per Ben]
#     - $FX/addonmodules/clamavconnector/trunk/Cpanel/ClamScanner.pm
#           [Used for publishing to httpupdate]
# Whenever a new change is applied, both copies of this module need to be updated
# with the same change and kept in sync.
#-------------------------------------------------------------------------------

=head1 MODULE

C<Cpanel::ClamScanner>

=head1 DESCRIPTION

C<Cpanel::ClamScanner> allows interaction with the clamd service to scan files for viruses.

=cut

use cPstrict;

use Cpanel::Imports;

use Cpanel                                  ();
use Cpanel::Alarm                           ();
use Cpanel::Binaries                        ();
use Cpanel::Encoder::Tiny                   ();
use Cpanel::JSON                            ();
use Cpanel::Exception                       ();
use Cpanel::Logger                          ();
use Cpanel::SafeDir::MK                     ();
use Cpanel::SafeFile                        ();
use Cpanel::SafeFind                        ();
use Cpanel::SafeRun::Object                 ();
use Cpanel::Server::Type::Role::MailReceive ();
use Fcntl                                   ();
use IO::Handle                              ();

our $VERSION = '1.2';

my $ClamScanner_bytescount    = 0;
my $ClamScanner_pbytescount   = 0;
my $ClamScanner_filecount     = 0;
my $ClamScanner_pfilecount    = 0;
my $ClamScanner_bars          = 0;
my $ClamScanner_infected      = 0;
my $ClamScanner_txtfile       = '';
my $ClamScanner_lastjsupdate  = 0;
my $ClamScanner_lastfjsupdate = 0;
my $ClamScanner_av;
our $ClamScanner_skip_role_checks = 0;

my $LOGGER                = Cpanel::Logger->new();
my $STATUS_FILE           = ".clamavconnector.status";
my $VIRUS_FILE            = ".clamavconnector.scan";
my $PID_FILE              = ".clamavconnector.pid";
my $DISINFECTION_LOG_FILE = ".clamavconnector.disinfection.log";
my $DISINFECTION_STATE    = ".clamavconnector.disinfection.state";

use constant _ENOENT => 2;

sub _role_is_enabled {
    return 1 if $ClamScanner_skip_role_checks;
    if ( !eval { Cpanel::Server::Type::Role::MailReceive->verify_enabled(); 1 } ) {
        $Cpanel::CPERROR{$Cpanel::context} = $@->to_locale_string_no_id();
        return undef;
    }

    return 1;
}

sub ClamScanner_init {
    return 1;
}

sub ClamScanner_disinfectlist {
    return if !_role_is_enabled();

    if ( open my $ifl_fh, "<", "$Cpanel::homedir/.clamavconnector.scan" ) {
        my $n = 0;
        while ( readline($ifl_fh) ) {
            $n++;
            chomp;
            my ( $file, $virus ) = /(.*)=([^=]+)/;
            $file = _decode_filename($file);
            my $html_safe_file  = Cpanel::Encoder::Tiny::safe_html_encode_str($file);
            my $html_safe_virus = Cpanel::Encoder::Tiny::safe_html_encode_str($virus);
            print "<tr>";
            print "<td>$html_safe_file</td><td>$html_safe_virus</td>";
            my $dc = 'checked';

            if ( $file =~ /^mail\// ) {
                $dc = '';
                print "<td><input type=radio name=\"action-${n}\" checked value=x></td>";
            }
            else {
                print "<td></td>";
            }
            print "<td><input type=radio name=\"action-${n}\" $dc value=q></td>";
            print "<td><input type=radio name=\"action-${n}\" value=d></td>";
            print "<td><input type=radio name=\"action-${n}\" value=i></td>";
            print "</tr>";
        }
        close $ifl_fh;
    }

    return;
}

sub ClamScanner_main {
    return if !_role_is_enabled();

    my @perms = _getperms();
    if ( !@perms ) {
        print "<p><b>ClamAV scanner has been disabled for this account.</b></p>\n";
        return;
    }
    my $now = time();
    if ( ( ( ( stat("$Cpanel::homedir/.clamavconnector.scan") )[9] // 0 ) + 600 ) <= $now ) {
        unlink("$Cpanel::homedir/.clamavconnector.scan");
    }
    else {
        print "Virus Scan Already In Progress!  Please wait till it completes and then reload this page.\n";
        return;
    }

    print "<center>Detecting Status....</center>";

    if ( -e "$Cpanel::homedir/.clamavconnector.scan" ) {
        print "<script>document.location.href = 'disinfect.html';</script>\n\n\n\n";
    }
    else {
        print "<script>document.location.href = '../clam-av/';</script>\n\n\n\n";
    }
    return;
}

sub ClamScanner_getsocket {
    my $clamd = shift;

    return if !_role_is_enabled();

    $clamd //= find_clamd();
    my $run = Cpanel::SafeRun::Object->new(
        'program' => 'strings',
        'args'    => [$clamd],
    );

    my $conf = -e '/usr/local/cpanel/3rdparty/etc/clamd.conf' ? '/usr/local/cpanel/3rdparty/etc/clamd.conf' : '/etc/clamd.conf';

    if ( $run && ( $run->stdout() =~ /^(.*\/clam(?:av|d).conf)/m ) ) {
        $conf = $1;
    }

    return _read_socket_from_conf($conf);
}

sub _read_socket_from_conf {
    my $conf   = shift;
    my $socket = '/var/clamd';

    if ( open( my $conf_fh, "<", $conf ) ) {
        while ( my $line = <$conf_fh> ) {
            if ( $line =~ /^[\s\t]*LocalSocket[\s\t]*(\S+)/i ) {
                $socket = $1;
            }
        }
        close($conf_fh);
    }
    return $socket;
}

sub find_clamd {
    my $clamd_bin = Cpanel::Binaries::path("clamd");
    -x $clamd_bin or die Cpanel::Exception::create(
        'Plugin::NotInstalled',
        [ 'plugin' => 'ClamAV' ],
    );

    return $clamd_bin;
}

sub ClamScanner_scanhomedir {
    my ($scanarg) = @_;

    return if !_role_is_enabled();

    my $alarm = Cpanel::Alarm->new(
        86400,
        sub {
            print '<script>alert("The scan timed out.  Please try again with fewer files.");</script>';
            print "<script>parent.document.location.href = 'disinfect.html';</script>\n\n\n\n";

            # If we don't exit, the scan may continue on in the background.
            exit;
        }
    );
    setpriority( 0, 0, 19 );

    $| = 1;

    my $scandir = $Cpanel::homedir;
    if ( $scanarg eq "pubftp" )  { $scandir .= "/public_ftp"; }
    if ( $scanarg eq "pubhtml" ) { $scandir .= "/public_html"; }
    if ( $scanarg eq "mail" )    { $scandir .= "/mail"; }

    if ( -e "$Cpanel::homedir/.clamavconnector.scan" ) {
        print "<script>alert('Virus Scan Already In Progress!  Please wait till it completes before scanning again.');</script>\n\n\n";
        print "<script>parent.document.location.href = 'index.html';</script>\n\n\n\n";
    }

    my $port = ClamScanner_getsocket();
    _jscfileupdate('... connecting to clamd service ...');

    if ( !$INC{'File/Scan/ClamAV.pm'} ) {
        require File::Scan::ClamAV;
    }

    $ClamScanner_av = File::Scan::ClamAV->new( find_all => 1, port => $port );
    if ( $ClamScanner_av->ping ) {
        _jscfileupdate('... connected to clamd service ...');
        open( my $virus_fh, ">", "$Cpanel::homedir/.clamavconnector.scan" )
          or die Cpanel::Exception::create(
            "IO::FileOpenError",
            'The system cannot open the “[_1]” file to write to it: [_2]',
            [ "$Cpanel::homedir/.clamavconnector.scan", $! ],
          );
        Cpanel::SafeFind::finddepth( { 'wanted' => \&ClamScanner_filecount, 'no_chdir' => 1 }, $scandir );
        my $tbytes = int( $ClamScanner_bytescount / 1024 / 1024 );
        print qq{<script>
        if (parent.frames.mainfr) {
            parent.frames.mainfr.document.viriiform.tfilen.value = '$ClamScanner_filecount';
            parent.frames.mainfr.document.viriiform.tbytes.value = '$tbytes';
        }
        </script>};

        my %send_args = ( virus_fh => $virus_fh );
        Cpanel::SafeFind::finddepth(
            {
                'wanted'   => sub { ClamScanner_processfile(%send_args) },
                'no_chdir' => 1
            },
            $scandir
        );
        close($virus_fh);
        _jscfileupdate("... scan complete $ClamScanner_filecount files scanned.");
        print qq{
<script>
    if (parent.frames.mainfr) {
    parent.frames.mainfr.bars.document.location.href='bars.html?bars=45';
    parent.frames.mainfr.document.viriiform.percent.value = '100';
    }
    </script>
        };

        if ($ClamScanner_infected) {
            print "<script>alert('Virus Scan Complete.  $ClamScanner_infected infected files found.');</script>\n\n";
            print "<script>parent.document.location.href='disinfect.html';</script>\n\n";
        }
        else {
            unlink("$Cpanel::homedir/.clamavconnector.scan");
            print qq{
    <script>
        alert('Virus Scan Complete.  No Virus Found.');
        parent.document.location.href='index.html';
</script>
};
        }

    }
    else {
        print "Could not connect to clamd\n";
    }

    return;
}

sub ClamScanner_filecount {
    return if !_role_is_enabled();

    my $file = $File::Find::name;
    return if ( -l $file || -d $file || $file =~ m{^\Q$Cpanel::homedir\E/quarantine_clamavconnector/} );

    $ClamScanner_bytescount += ( stat(_) )[7];
    $ClamScanner_filecount++;

    return;
}

sub ClamScanner_processfile (%args) {
    return if !_role_is_enabled();

    my $async    = $args{async} // 0;
    my $virus_fh = $args{virus_fh} || die Cpanel::Exception::create( 'MissingParameter', [ name => 'virus_fh' ] );
    my $file     = $File::Find::name;
    return if ( -l $file || -d $file || $file =~ m{^\Q$Cpanel::homedir\E/quarantine_clamavconnector/} );
    $ClamScanner_pbytescount += ( stat(_) )[7];
    $ClamScanner_pfilecount++;

    my $cbytes = int( $ClamScanner_pbytescount / 1024 / 1024 );
    my ($virus);

    my $percent    = ( $ClamScanner_pbytescount / $ClamScanner_bytescount );
    my $bars       = int( 45 * $percent );
    my $txtpercent = int( $percent * 100 );
    if ( $bars == 0 ) { $bars = 1; }

    my $rlfile  = substr( $file, length($Cpanel::homedir) + 1 );
    my $txtfile = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    $txtfile =~ tr/\r\n//d;
    _jscfileupdate( $txtfile, $cbytes ) if !$async;

    $ClamScanner_txtfile = '';
    if ( $rlfile =~ /^mail\// ) {
        $ClamScanner_txtfile = $txtfile;
        $virus               = _scanmbox( $file, $async );
    }
    elsif ( _filename_is_unsafe($file) ) {
        ( undef, $virus ) = _scan_file_with_unsafe_name( $ClamScanner_av, $file );
    }
    else {
        $ClamScanner_txtfile = $txtfile;
        ( undef, $virus ) = $ClamScanner_av->scan($file);
    }

    if ( length $virus ) {
        $ClamScanner_infected++;
        if ( _filename_is_unsafe($rlfile) ) {
            print $virus_fh sprintf( "././unsafe:%s=%s\n", _encode_filename($rlfile), $virus );
        }
        else {
            print $virus_fh "${rlfile}=${virus}\n";
        }
        my $js_safe_text = Cpanel::JSON::SafeDump("$rlfile: $virus");

        if ($async) {
            my %ret = _get_processfile_return_data();
            $ret{current_file_is_infected} = 1;
            return %ret;
        }

        print qq{<script>
    if (parent.frames.mainfr) {
        parent.frames.mainfr.document.viriiform.status.options[parent.frames.mainfr.document.viriiform.status.options.length] = new Option($js_safe_text);
    }
        </script>
        };
    }
    elsif ($async) {
        my %ret = _get_processfile_return_data();
        $ret{current_file_is_infected} = 0;
        return %ret;
    }

    if ( $ClamScanner_bars != $bars ) {
        $ClamScanner_bars = $bars;
        print qq{<script>
        if (parent.frames.mainfr) {
                parent.frames.mainfr.bars.document.location.href='bars.html?bars=$ClamScanner_bars';\n
         }
        </script>
        };
    }
    _jscupdate( $ClamScanner_pfilecount, $cbytes, $txtpercent );
    return;
}

sub _get_processfile_return_data {
    my ( $self, $arguments ) = @_;
    return (
        current_file        => $arguments->{txtfile}     || $ClamScanner_txtfile,
        total_file_count    => $arguments->{filecount}   || $ClamScanner_filecount,
        scanned_file_count  => $arguments->{pfilecount}  || $ClamScanner_pfilecount,
        total_file_size_MiB => $arguments->{bytescount}  || $ClamScanner_bytescount,
        scanned_file_size   => $arguments->{pbytescount} || $ClamScanner_pbytescount,
    );
}

sub ClamScanner_bars {
    my ($bars) = @_;
    for ( my $i = 1; $i <= $bars; $i++ ) {
        print "<img src=blank.gif width=2 height=31>";
        print "<img src=bar.gif width=12 height=31>";
    }
    return;
}

=head2 _initialize_homedir()

Initialize the homedir if needed.

=cut

sub _initialize_homedir {
    if ( !$Cpanel::homedir ) {
        require Cpanel::PwCache;
        $Cpanel::homedir = Cpanel::PwCache::gethomedir();
    }
    return $Cpanel::homedir;
}

=head2 disinfection_log_path()

Fetches the path to the users disinfection log used while processing a Cpanel::ClamScanner::disinfect() call.

=cut

sub disinfection_log_path {
    _initialize_homedir();
    return "$Cpanel::homedir/$DISINFECTION_LOG_FILE";
}

=head2 disinfection_queued()

Leave a file behind that tells us the disinfection is queued.

=cut

sub disinfection_queued {
    my $disinfect_log_path = disinfection_log_path();
    if ( !unlink($disinfect_log_path) ) {
        if ( $! != _ENOENT() ) {
            die Cpanel::Exception::create(
                'IO::UnlinkError',
                'The system could not remove the “[_1]” file: [_2]',
                [ $disinfect_log_path, $! ],
            );
        }
    }
    open my $state_fh, '>', "$Cpanel::homedir/$DISINFECTION_STATE" or die $!;
    print $state_fh "queued\n";
    close $state_fh or die $!;
    return;
}

=head2 start_disinfection()

Leave a file behind that tells us the disinfection is running.

=cut

sub start_disinfection {
    open my $state_fh, '>', "$Cpanel::homedir/$DISINFECTION_STATE" or die $!;
    print $state_fh "running\n";
    close $state_fh or die $!;
    return;
}

=head2 finish_disinfection()

Clean up the state file.

=cut

sub finish_disinfection {
    unlink "$Cpanel::homedir/$DISINFECTION_STATE" or die $!;
    return;
}

=head2 get_disinfection_state()

Get the current disinfection state.

=cut

sub get_disinfection_state {
    my $state_fh;
    if ( !open $state_fh, '<', "$Cpanel::homedir/$DISINFECTION_STATE" ) {
        return 'none' if $! == _ENOENT();
    }

    my $state = do { local $/; <$state_fh> };
    chomp $state;
    close $state_fh or die $!;
    return $state;
}

=head2 validate_disinfect_actions(ACTIONS)

Various prechecks to run for the action passed to disinfect.

=cut

sub validate_disinfect_actions ($actions) {
    if ( !$actions || ref $actions ne 'HASH' || !keys %$actions ) {
        die Cpanel::Exception::create(
            'InvalidParameter',
            'The parameter “[_1]” is required and must be a non-empty [asis,hashref].',
            ['actions'],
        );
    }

    foreach my $key ( keys %$actions ) {
        if ( $actions->{$key} !~ m/^(quarantine|ignore|delete|cleanse_mailbox)$/ ) {
            die Cpanel::Exception::create(
                'InvalidParameter',
                '“[_1]” is not a valid “[_2]” parameter value. Select from one of the following: [list_or_quoted,_3]',
                [ $actions->{$key}, 'actions', [ 'quarantine', 'delete', 'ignore', 'cleanse_mailbox' ] ],
            );
        }
    }
    return;
}

=head2 disinfect(file1 => 'quarantine', file2 => 'delete')

Start a disinfection process in the background. The argument is a hash with file paths in the keys and the actions to take in the values.

We currently support:

=over

=item delete - remove the file from the file system.

=item ignore - ignore the file.

=item quarantine - move the file to the quarantine folder.

=item cleanse_mailbox - remove the dangerous stuff from the mailbox

=back

Any other options are ignored. Only files listed in the arguments will be processed.

=cut

sub disinfect (%actions) {

    validate_disinfect_actions( \%actions );

    _initialize_homedir();

    foreach my $key ( keys %actions ) {

        # We want to use home relative paths internally
        # so translate the inputs as needed.
        my $real_key = $key;
        $real_key =~ s{^\Q$Cpanel::homedir\E/}{};
        if ( $real_key ne $key ) {
            $actions{$real_key} = delete $actions{$key};
        }
    }

    my $disinfect_log_path = disinfection_log_path();
    if ( !unlink($disinfect_log_path) ) {
        if ( $! != _ENOENT() ) {
            die Cpanel::Exception::create(
                'IO::UnlinkError',
                'The system could not remove the “[_1]” file: [_2]',
                [ $disinfect_log_path, $! ],
            );
        }
    }

    my $disinfection_log_fh      = IO::Handle->new();
    my $disinfection_log_fh_lock = Cpanel::SafeFile::safeopen( $disinfection_log_fh, '>', $disinfect_log_path );
    if ( !$disinfection_log_fh_lock ) {
        die Cpanel::Exception::create(
            "IO::FileOpenError",
            'The system cannot open the “[_1]” file to write to it: [_2]',
            [ $disinfect_log_path, $! ],
        );
    }

    require JSON;
    my $JSON = JSON->new;

    # helper method to simplify report steps
    my $id     = 0;
    my $report = sub ($data) {
        $data->{id} = ++$id;

        say $disinfection_log_fh $JSON->encode($data);
        return;
    };

    my $infected_files_log_path = "$Cpanel::homedir/.clamavconnector.scan";
    if ( !-e $infected_files_log_path || -z _ ) {
        $report->( { type => 'done', state => 'info', message => locale()->maketext('No infected files found') } );
        Cpanel::SafeFile::safeclose( $disinfection_log_fh, $disinfection_log_fh_lock );
        return;
    }

    my $infected_files_log_fh;
    if ( !open( $infected_files_log_fh, "<", $infected_files_log_path ) ) {
        $report->(
            {
                type    => 'done',
                state   => 'error',
                message => locale()->maketext(
                    'The system failed to open the file “[_1]” for reading because of an error: [_2]',
                    $infected_files_log_path, $!
                ),
            }
        );
        Cpanel::SafeFile::safeclose( $disinfection_log_fh, $disinfection_log_fh_lock );
        return;
    }

    start_disinfection();
    while ( readline($infected_files_log_fh) ) {
        chomp();

        # Filename may contain "=" and the "=" separator should be the last occurrence
        # (Usage of greedy pattern is needed.)
        my ( $file, $virus ) = /(.*)=([^=]+)/;
        $file = _decode_filename($1);

        if ( !$actions{$file} || $actions{$file} eq 'ignore' ) {
            $report->( { type => 'step', file => $file, state => 'no-action', message => locale()->maketext('No action specified for file.') } );
        }
        elsif ( $actions{$file} eq 'delete' ) {
            if ( !unlink("${Cpanel::homedir}/${file}") ) {
                $report->(
                    {
                        type    => 'step',
                        file    => $file,
                        state   => 'error',
                        message => locale()->maketext(
                            'The system could not remove the “[_1]” file: [_2]',
                            "${Cpanel::homedir}/${file}", $!
                        ),
                    }
                );
            }
            else {
                $report->( { type => 'step', file => $file, state => 'deleted' } );
            }
        }
        elsif ( $actions{$file} eq 'quarantine' ) {
            my $safefile = $file;
            $safefile =~ s/\//_/g;
            my $path            = "${Cpanel::homedir}/${file}";
            my $quarantine_path = "${Cpanel::homedir}/quarantine_clamavconnector/$safefile";

            if ( !-e "${Cpanel::homedir}/quarantine_clamavconnector" ) {
                mkdir( "${Cpanel::homedir}/quarantine_clamavconnector", 0700 );
            }

            if ( !rename( $path, $quarantine_path ) ) {
                $report->(
                    {
                        type    => 'step',
                        file    => $file,
                        state   => 'error',
                        message => locale()->maketext(
                            'The system failed to move the file “[_1]” to “[_2]” because of an error: [_3]',
                            $path, $quarantine_path, $!
                        ),
                    }
                );
            }
            else {
                $report->( { type => 'step', file => $file, state => 'quarantined' } );
            }
        }
        elsif ( $actions{$file} eq 'cleanse_mailbox' ) {
            if ( $file !~ m{^mail/} ) {
                $report->(
                    {
                        type    => 'step',
                        file    => $file,
                        state   => 'error',
                        message => locale()->maketext(
                            'The file “[_1]” is not in a mailbox.',
                            $file
                        ),
                    }
                );
            }
            else {

                ClamScanner_cleansembox( ${Cpanel::homedir} . "/" . $file, undef, $report );
                $report->( { type => 'step', file => $file, state => 'mailbox-cleansed' } );
            }
        }
    }

    if ( !close($infected_files_log_fh) ) {
        $report->(
            {
                type    => 'issue',
                state   => 'warning',
                message => locale()->maketext(
                    'The system received the following error when closing the file handle for “[_1]”: [_2]',
                    $infected_files_log_path, $!
                ),
            }
        );
    }
    if ( !unlink($infected_files_log_path) ) {
        if ( $! != _ENOENT() ) {
            $report->(
                {
                    type    => 'issue',
                    state   => 'warning',
                    message => locale()->maketext(
                        'The system could not remove the “[_1]” file: [_2]',
                        $infected_files_log_path, $!
                    ),
                }
            );
        }
    }

    $report->( { type => 'done', state => 'success' } );
    finish_disinfection();
    Cpanel::SafeFile::safeclose( $disinfection_log_fh, $disinfection_log_fh_lock );

    return;
}

=head2 load_disinfection_log($LAST_ID = undef)

Load the entries in the disinfection log. If you pass the $LAST_ID, only entries
after this last id are returned. If there are no entries after the $LAST_ID, an empty array is returned.

=cut

sub load_disinfection_log ( $last_id = undef ) {

    require Cpanel::JSON;

    my $disinfect_log_path       = disinfection_log_path();
    my $disinfection_log_fh      = IO::Handle->new();
    my $disinfection_log_fh_lock = Cpanel::SafeFile::safeopen( $disinfection_log_fh, '<', $disinfect_log_path );
    if ( !$disinfection_log_fh_lock ) {
        return [];
    }

    my @log;
    my $id = 0;
    while ( my $line = readline($disinfection_log_fh) ) {
        chomp $line;

        my $entry = Cpanel::JSON::Load($line);

        $id++;
        if ( !defined $last_id || $id > $last_id ) {
            push @log, $entry;
        }
    }

    Cpanel::SafeFile::safeclose( $disinfection_log_fh, $disinfection_log_fh_lock );

    return \@log;
}

sub ClamScanner_cleansembox {
    my ( $mbox, $async, $report ) = @_;

    return if !_role_is_enabled();

    my $port = ClamScanner_getsocket();

    if ( !$INC{'File/Scan/ClamAV.pm'} ) {
        require File::Scan::ClamAV;
    }

    $ClamScanner_av = File::Scan::ClamAV->new(
        'find_all' => 1,
        'port'     => $port
    );

    if ( $ClamScanner_av->ping ) {

        my $message = 0;

        my $mbox_fh;
        my $clean_mbox_fh;

        # Processing input $mbox
        if ( !open( $mbox_fh, "<", $mbox ) ) {
            $report->(
                {
                    type    => 'issue',
                    state   => 'error',
                    message => locale()->maketext( 'The system failed to open the file “[_1]” because of an error: [_2]', $mbox, $! ),
                }
            );

            return;
        }

        # Using output file $mbox.clamavconnector_clean as holder
        my $clean_mbox_filepath = ${mbox} . '.clamavconnector_clean';
        if (
            !sysopen(
                $clean_mbox_fh,                                                                $clean_mbox_filepath,
                Fcntl::O_WRONLY() | Fcntl::O_TRUNC() | Fcntl::O_CREAT() | Fcntl::O_NOFOLLOW(), 0600
            )
        ) {
            $report->(
                {
                    type    => 'issue',
                    state   => 'error',
                    message => locale()->maketext( 'The system failed to open the file “[_1]” because of an error: [_2]', $clean_mbox_filepath, $! ),
                }
            );
        }

        # Using output file ${mbox}.clamscan.tmp.${message} for each mail message
        my $st_fh;
        my $mbox_tmp_msg_filepath = $mbox . '.clamscan.tmp.' . $message;
        if (
            !sysopen(
                $st_fh,                                                                        $mbox_tmp_msg_filepath,
                Fcntl::O_WRONLY() | Fcntl::O_TRUNC() | Fcntl::O_CREAT() | Fcntl::O_NOFOLLOW(), 0600
            )
        ) {
            $report->(
                {
                    type    => 'issue',
                    state   => 'error',
                    message => locale()->maketext( 'The system failed to open the file “[_1]” because of an error: [_2]', $mbox_tmp_msg_filepath, $! ),
                }
            );
        }

        my $virus;
        my $line;
        while ( $line = readline($mbox_fh) ) {
            if ( $line =~ /^From\s+\S+\s+\S+\s+\S+\s+\d+\s+\d+:\d+:\d+\s+\d+/ ) {

                close($st_fh);
                $virus = _checkvirus( $mbox, $message, $async );
                _recvirus( $mbox, $virus, $message, $clean_mbox_fh );
                _cleanvtmp( $mbox, $message );

                # Process next message.
                $message++;
                my $mbox_tmp_msg_filepath = $mbox . '.clamscan.tmp.' . $message;
                if (
                    !sysopen(
                        $st_fh,                                                                        "${mbox}.clamscan.tmp.${message}",
                        Fcntl::O_WRONLY() | Fcntl::O_TRUNC() | Fcntl::O_CREAT() | Fcntl::O_NOFOLLOW(), 0600
                    )
                ) {
                    $report->(
                        {
                            type    => 'issue',
                            state   => 'error',
                            message => locale()->maketext( 'The system failed to open the file “[_1]” because of an error: [_2]', $mbox_tmp_msg_filepath, $! ),
                        }
                    );
                }
            }

            if ( !print {$st_fh} $line ) {
                $report->(
                    {
                        type    => 'issue',
                        state   => 'error',
                        message => locale()->maketext( 'The system failed to write to the file “[_1]” because of an error: [_2]', $mbox_tmp_msg_filepath, $! ),
                    }
                );
            }
        }

        close($mbox_fh);

        # Process remaining data
        close($st_fh);
        $virus = _checkvirus( $mbox, $message, $async );
        _recvirus( $mbox, $virus, $message, $clean_mbox_fh );
        _cleanvtmp( $mbox, $message );

        close($clean_mbox_fh);

        # Update mbox using the clean one
        my $mbox_clean_filepath = $mbox . '.clamavconnector_clean';
        if (
            !sysopen(
                $clean_mbox_fh,
                $mbox_clean_filepath,
                Fcntl::O_RDONLY() | Fcntl::O_NOFOLLOW()
            )
        ) {
            $report->(
                {
                    type    => 'issue',
                    state   => 'error',
                    message => locale()->maketext( 'The system failed to write to the file “[_1]” because of an error: [_2]', $mbox_clean_filepath, $! ),
                }
            );
        }

        my $out_mbox_fh = IO::Handle->new();
        my $mboxlock    = Cpanel::SafeFile::safeopen( $out_mbox_fh, ">", "$mbox" );
        if ( !$mboxlock ) {
            $report->(
                {
                    type    => 'issue',
                    state   => 'error',
                    message => locale()->maketext( 'Could not write to mbox file “[_1]”.', $mbox ),
                }
            );
            return;
        }

        # Update mbox with the clean data from clean_mbox_fh
        while ( $line = readline($clean_mbox_fh) ) {
            print {$out_mbox_fh} $line;
        }
        Cpanel::SafeFile::safeclose( $out_mbox_fh, $mboxlock );
        close($clean_mbox_fh);

        unlink($mbox_clean_filepath);
    }
    return;
}

sub ClamScanner_printScans {
    return if !_role_is_enabled();

    my $locale = locale();

    my @perms = _getperms();
    if ( !@perms ) {
        print "<p><b>ClamAV Scanner has been disabled for this account.</b></p>\n";
        return;
    }

    print q[<table align="center" cellspacing="0" cellpadding="2" border="0">];
    print qq[<form action="scanner.html">\n];

    my $message = "";
    my $checked = "";
    foreach my $perm (@perms) {

        if ( $perm eq "mail" ) {
            $perm    = "mail";
            $message = $locale->maketext('Scan Mail');
            $checked = " CHECKED";
        }
        elsif ( $perm eq "homedir" ) {
            $perm    = "home";
            $message = $locale->maketext('Scan Entire Home Directory');
            $checked = "";
        }
        elsif ( $perm eq "pubhtml" ) {
            $perm    = "pubhtml";
            $message = $locale->maketext('Scan Public Web Space');
            $checked = "";
        }
        elsif ( $perm eq "pubftp" ) {
            $perm    = "pubftp";
            $message = $locale->maketext('Scan Public FTP Space');
            $checked = "";
        }
        else {
            next;
        }
        my $id = qq[scanpath$perm];
        print qq[<tr>\n<td>];
        print qq[<input type="radio" id="$id" name="scanpath" value="$perm"${checked}><label for="$id">&nbsp;${message}</label></input>\n];
        print qq[</td></tr>\n];
    }
    print qq[<tr><td>&nbsp;</td></tr>\n];
    my $scan_now = $locale->maketext('Scan Now');
    print qq[<tr><td><input class="input-button" type="submit" value="$scan_now"></input></td></tr>\n];
    print qq[</form></table>\n];

    return;
}

################################################################################
# _getperms
################################################################################

sub _getperms {
    my %conf;
    my @perms = qw/ mail homedir pubhtml pubftp /;

    if ( -e "/usr/local/cpanel/3rdparty/etc/cpclamav.conf" ) {
        open( CONF, "<", "/usr/local/cpanel/3rdparty/etc/cpclamav.conf" );
        while (<CONF>) {
            chomp();
            my ( $var, $val ) = split( /=/, $_ );
            $conf{$var} = $val;
        }
        close(CONF);
    }
    else {
        return (@perms);
    }

    if ( defined( $conf{'CLAMAVOVERRIDEUSERS'} ) ) {
        my @overrideusers = split( /,/, $conf{'CLAMAVOVERRIDEUSERS'} );
        foreach my $user (@overrideusers) {
            if ( $user eq $Cpanel::user ) {
                if ( -e "/var/cpanel/users/" . $user ) {
                    open( CONF, "/var/cpanel/users/" . $user ) or return undef;
                    my @u_conf = <CONF>;
                    close(CONF);
                    @u_conf = map { chomp; $_ } @u_conf;
                    my %conf;
                    foreach my $line (@u_conf) {
                        next if ( $line =~ /^[\s\t]*$/ );
                        my ( $var, $val ) = split( /=/, $line );
                        $conf{$var} = $val;
                    }
                    if ( defined( $conf{'CLAMAVSCANS'} ) ) {
                        @perms = grep { $_ } split( /,/, $conf{'CLAMAVSCANS'} );
                        return (@perms);
                    }
                }
                last;
            }
        }
    }

    if ( defined( $conf{'DEFAULTSCANS'} ) ) {
        @perms = grep { $_ } split( /,/, $conf{'DEFAULTSCANS'} );
        return (@perms);
    }
    else {
        return (@perms);
    }
}

sub _scanmbox ( $mbox, $async ) {

    my $message  = 0;
    my $open_res = open( my $mbox_fh, "<", $mbox );
    my $line;

    if ( $mbox =~ m{/(?:cur|new)/[^/]+\z} ) {
        my @filepath     = split( /\//, $mbox );
        my $file         = pop(@filepath);
        my $path         = join( '/', @filepath );
        my $clam_tmp_dir = "${path}/../tmp";
        $mbox = "${clam_tmp_dir}/${file}";
        Cpanel::SafeDir::MK::safemkdir($clam_tmp_dir) if !-d $clam_tmp_dir;
    }

    my $st_fh;
    if (
        !sysopen(
            $st_fh,                                                                        "${mbox}.clamscan.tmp.${message}",
            Fcntl::O_WRONLY() | Fcntl::O_TRUNC() | Fcntl::O_CREAT() | Fcntl::O_NOFOLLOW(), 0600
        )
    ) {
        $LOGGER->warn("Could not open file \"${mbox}.clamscan.tmp.${message}\"");
    }

    while ( $line = readline($mbox_fh) ) {
        if ( $line =~ /^From\s+\S+\s+\S+\s+\S+\s+\d+\s+\d+:\d+:\d+\s+\d+/ ) {

            # Process the current tmp file
            close($st_fh);
            my $virus = _checkvirus( $mbox, $message, $async );
            _cleanvtmp( $mbox, $message );    # Clean up the st_fh temp file after virus check
            if ( length $virus ) { return ($virus); }

            # Moving to the next one
            $message++;
            if (
                !sysopen(
                    $st_fh,                                                                        "${mbox}.clamscan.tmp.${message}",
                    Fcntl::O_WRONLY() | Fcntl::O_TRUNC() | Fcntl::O_CREAT() | Fcntl::O_NOFOLLOW(), 0600
                )
            ) {
                $LOGGER->warn("Could not open file \"${mbox}.clamscan.tmp.${message}\"");
            }
        }

        if ( !print {$st_fh} $line ) {
            $LOGGER->warn("Could not print line to file : $!");
        }
    }
    close($mbox_fh);

    # Process remaining data
    close($st_fh);
    my $virus = _checkvirus( $mbox, $message, $async );
    _cleanvtmp( $mbox, $message );    # Clean up the st_fh temp file after virus check
    return $virus if length $virus;

    return ("");
}

sub _recvirus {
    my ( $file, $virus, $message, $clean_mbox_fh ) = @_;
    if ( $virus ne "" ) {
        print "..purged message $message (infected with $virus)..\n";
    }
    else {
        my $line = '';
        open( my $st_fh, "<", "${file}.clamscan.tmp.$message" );
        while ( $line = readline($st_fh) ) {
            print {$clean_mbox_fh} $line;
        }
        close($st_fh);
        print ".\n";
    }
    return;
}

sub _cleanvtmp {
    my ( $file, $message ) = @_;
    unlink("${file}.clamscan.tmp.${message}");
    return;
}

sub _checkvirus ( $file, $message, $async ) {
    if ( !-e "${file}.clamscan.tmp.${message}" ) {
        $LOGGER->info("No such file ${file}.clamscan.tmp.${message} to scan!");
        return;
    }
    return if -z _;

    if ( $ClamScanner_txtfile ne "" && !$async ) {
        _jscfileupdate("$ClamScanner_txtfile (Message ${message})");
    }

    my ( $result, $virus ) = $ClamScanner_av->scan("${file}.clamscan.tmp.${message}");

    return ($virus);
}

sub _jscfileupdate {
    my ( $jsfile, $size ) = @_;
    my $js_safe_jsfile = Cpanel::JSON::SafeDump($jsfile);
    my $now            = time();

    if ( !defined $size || $size > 10 || $ClamScanner_lastjsupdate < $now ) {
        print qq{
    <script>

    if (parent.frames.mainfr) {
        if (parent.frames.mainfr.document.viriiform.cfile) {
            parent.frames.mainfr.document.viriiform.cfile.value = $js_safe_jsfile;
        }
        if (parent.frames.mainfr.document.getElementById('viriifile')) {
            parent.frames.mainfr.document.getElementById('viriifile').innerHTML = $js_safe_jsfile;
        }
    }
        </script>};
        $ClamScanner_lastjsupdate = $now;
    }
}

sub _jscupdate {
    my ( $cfilen, $cbytes, $percent ) = @_;
    my $now = time();

    if ( $ClamScanner_lastfjsupdate < $now ) {
        print qq{
<script>
if (parent.frames.mainfr) {
    parent.frames.mainfr.document.viriiform.cfilen.value = '$cfilen';
    parent.frames.mainfr.document.viriiform.cbytes.value = '$cbytes';
    parent.frames.mainfr.document.viriiform.percent.value = '$percent';
}
</script>};

        $ClamScanner_lastfjsupdate = $now;
    }
}

sub _filename_is_unsafe {
    my ($filename) = @_;
    return 1 if $filename =~ tr/\r\n//;
    return;
}

sub _encode_filename {
    my $file = shift;
    $file =~ s{^\Q$Cpanel::homedir\E/}{};    # optional, but need to assume it will be stripped off
    return join( ',', map { ord($_) } split //, $file );
}

sub _decode_filename {
    my $input = shift;
    if ( $input =~ m{^\./\./unsafe:([0-9,]+)} ) {
        my $encoded = $1;
        return join( '', map { chr($_) } split /,/, $encoded );
    }
    return $input;
}

sub _scan_file_with_unsafe_name {
    my ( $av, $file ) = @_;
    my $identifier = _encode_filename($file);
    my $temp       = sprintf( '%s/.ClamScanner_tmp_%s', $Cpanel::homedir, $identifier );
    if ( !link( $file, $temp ) ) {
        die "File has an unsafe name, and unable to create safe temp file for scanning: $!";
    }
    my @result = $av->scan($temp);
    unlink $temp;
    return @result;
}

sub _scan_paths_for_home_dir ( $self, $home_dir = $Cpanel::homedir ) {
    return (
        home        => $home_dir,
        public_ftp  => "$home_dir/public_ftp",
        public_html => "$home_dir/public_html",
        mail        => "$home_dir/mail",
    );
}

## OO interface. This uses some non-OO code above for now.

=head1 SYNOPSIS

    my $scanner = Cpanel::ClamScanner->new();
    $scanner->scan_files('home');
    my $status = $scanner->get_scan_status();

=cut

sub new ( $class, %args ) {
    $args{home_dir} = $Cpanel::homedir if !$args{home_dir};
    $ClamScanner_skip_role_checks = $args{skip_role_checks};

    my $self = {
        debug         => $args{debug} || 0,
        home_dir      => $args{home_dir},
        status_file   => "$args{home_dir}/$STATUS_FILE",
        virus_file    => "$args{home_dir}/$VIRUS_FILE",
        pid_file      => "$args{home_dir}/$PID_FILE",
        status_data   => {},
        virus_fh      => undef,
        _pid_handler  => undef,
        _clam_handler => undef,
    };
    return bless $self, $class;
}

=head1 METHODS

=head2 scan_files

Initiates a clam scan and returns immediately

=head3 ARGUMENTS

=over

=item scan_type - string

One of: home, public_html, public_ftp, mail

=back

=cut

# This is a copy of ClamScanner_scanhomedir, without the printing
sub scan_files ( $self, $scan_type ) {
    my $locale   = locale();
    my $scan_dir = $self->_get_scan_path_for_type($scan_type);
    local $ClamScanner_skip_role_checks = $self->{skip_role_checks};

    $self->_reset_status();
    $self->_write_status();

    if ( $self->_scan_is_running() ) {
        die Cpanel::Exception::create(
            'CommandAlreadyRunning',
            'A virus scan is already in progress! Please wait until it completes before scanning again.',
        );
    }

    # delete results file if older than 10 min
    if ( $self->_scan_file_is_old() ) {
        unlink( $self->{'virus_file'} );
    }

    $ClamScanner_av = $self->_get_clam_handler();

    require Cpanel::ForkAsync;

    my $child_pid = Cpanel::ForkAsync::do_in_child(
        sub {
            open( \*STDIN,  '<', '/dev/null' );                                                                   ## no critic qw(RequireCheckedOpen)
            open( \*STDOUT, '>', $self->{debug} ? "$self->{home_dir}/.clamavconnector.stdout" : '/dev/null' );    ## no critic qw(RequireCheckedOpen)
            open( \*STDERR, '>', $self->{debug} ? "$self->{home_dir}/.clamavconnector.stderr" : '/dev/null' );    ## no critic qw(RequireCheckedOpen)

            # Set up the file handle for the old list of viruses so ClamScanner_processfile can write to it
            open( $self->{virus_fh}, '>', $self->{virus_file} ) or die Cpanel::Exception::create(
                "IO::FileOpenError",
                'The system cannot open the “[_1]” file to write to it: [_2]',
                [ $self->{virus_file}, $! ],
            );
            Cpanel::SafeFind::finddepth( { 'wanted' => \&ClamScanner_filecount, 'no_chdir' => 1 }, $scan_dir );

            $self->_update_status(
                total_file_count    => $ClamScanner_filecount,
                total_file_size_MiB => int( $ClamScanner_bytescount / 1024 / 1024 ),
            );
            $self->_write_status();

            # runs the scan on each file found
            Cpanel::SafeFind::finddepth( { 'wanted' => sub { $self->_scan_one_file() }, 'no_chdir' => 1 }, $scan_dir );

            $self->_update_status(
                current_file  => '',
                scan_complete => 1,
            );
            $self->_write_status();

            close( $self->{virus_fh} );
            $self->_clean_pid_file();
            $self->_clean_virus_file();
        }
    );

    $self->_create_pid_file($child_pid);

    return;
}

=head2 _scan_one_file

Scan one file and update current clam-run status/virus files based on results.

This is subroutine given to File::Find, which runs this sub against each file it finds.

=head3 ARGUMENTS

None.

This requires no arguments because File::Find has a variable 'name', which has the name of the file this sub will act upon.

=cut

sub _scan_one_file ($self) {
    my %latest_data = ClamScanner_processfile(
        async    => 1,
        virus_fh => $self->{virus_fh},
    );

    my $current_file_is_infected = delete $latest_data{'current_file_is_infected'};

    $self->_add_infected_file( $latest_data{'current_file'} ) if $current_file_is_infected;
    $self->_update_status(%latest_data);
    $self->_write_status();

    return;
}

=head2 get_scan_status

Return results of current or latest clam scan, defined by status file.

Example:

    $status = {
        'contents' => {
            'time_started'        => 1608816662,
            'scan_complete'       => 0,
            'total_file_count'    => 136,
            'scanned_file_count'  => 43,
            'total_file_size_MiB' => 364085500,
            'scanned_file_size'   => 12287390,
            'current_file'        => '/home/username/pathtoa/file',
            'infected_files' => [
                                  '/home/username/abad/file',
                                  '/home/username/andanotherone'
                                ]
        }
    };

=cut

sub get_scan_status ($self) {
    my %result;

    if ( -s $self->{'status_file'} ) {
        eval { $result{'contents'} = Cpanel::JSON::SafeLoadFile( $self->{'status_file'} ) } or die Cpanel::Exception::create(
            'JSONParseError',
            "The system failed to read the scan status from “[_1]”. This may indicate the scan status data is missing or corrupt.",
            [ $self->{'status_file'} ],
        );
    }
    else {
        $result{'message'} = locale()->maketext('No active scans.');
    }

    return \%result;
}

=head1 METHODS

=head2 get_scan_types

Retrieve a list of virus scan types that are available to the current user.

This subroutine uses the _getperms() private subroutine to retrieve this information.

=head3 RETURNS

=over

=item SCAN TYPES - Array of strings

An array of strings containing the scan types available to the user.

Possible scan types include "home", "public_html", "public_ftp", and "mail".

Example:

    $available_scan_types = {
        [
            'mail',
            'public_html'
        ]
    };

=back

=cut

sub get_scan_types {
    my @available_scan_types = _getperms() or die Cpanel::Exception::create(
        'InvalidParameter',
        '[asis,ClamAV®] is disabled for this account.'
    );
    my %old_to_new_scan_types = (
        'homedir' => 'home',
        'mail'    => 'mail',
        'pubftp'  => 'public_ftp',
        'pubhtml' => 'public_html',
    );
    return [ sort map { $_ || die locale()->maketext('Invalid [asis,ClamAV®] scan type configuration in [asis,cpclamav.conf].') . "\n" } @old_to_new_scan_types{@available_scan_types} ];
}

=head1 METHODS

=head2 list_infected_files

Retrieve an array of hashes containing information for infected files on the system.

=head3 RETURNS

=over

=item INFECTED FILES - Array of hashes

An array of hashes containing information on infected files.

Each has contains the filename (file) and the virus type (virus).

Example:

    $infected_files = [
        {
            file: /path/to/virus
            virus: Win.Test.EICAR_HDB-1
        }
    ];

=back

=cut

sub list_infected_files ($self) {
    my %result = ( 'data' => [] );

    if ( -s $self->{'virus_file'} ) {
        open( my $infected_file_list, "<", $self->{'virus_file'} ) or die Cpanel::Exception::create(
            "IO::FileOpenError",
            'The system failed to open the file “[_1]” for reading because of an error: [_2]',
            [ $self->{'virus_file'}, $! ],
        );

        while ( my $line = <$infected_file_list> ) {
            chomp($line);
            my ( $file, $virus ) = $line =~ /(.*)=([^=]+$)/;
            if ( !$file || !$virus ) {
                $result{'warning'} = locale()->maketext(
                    'Failed to read one or more lines from “[_1]”. This may indicate the infected file entries are invalid or corrupt.',
                    $self->{'virus_file'}
                );
            }
            else {
                $file = $self->{home_dir} . '/' . _decode_filename($file);
                my $html_safe_file  = Cpanel::Encoder::Tiny::safe_html_encode_str($file);
                my $html_safe_virus = Cpanel::Encoder::Tiny::safe_html_encode_str($virus);
                push @{ $result{'data'} }, { 'file' => $html_safe_file, 'virus_type' => $html_safe_virus };
            }
        }

        close($infected_file_list);
    }

    return \%result;
}

sub _get_scan_path_for_type ( $self, $scan_type ) {
    my %scan_paths = $self->_get_scan_paths();
    grep( $_ eq $scan_type, ( keys %scan_paths ) ) or die Cpanel::Exception::create(
        'InvalidParameter',
        '“[_1]” is not a valid “[_2]” parameter value. Select from one of the following: [list_or_quoted,_3]',
        [ $scan_type, 'scan_type', [ keys %scan_paths ] ],
    );
    _user_can_run_scan_type_or_die($scan_type);

    return $scan_paths{$scan_type};
}

sub _get_scan_paths ($self) {
    return _scan_paths_for_home_dir( $self->{home_dir} );
}

sub _user_can_run_scan_type_or_die ($scan_type) {
    grep( $_ eq $scan_type, @{ get_scan_types() } ) or die Cpanel::Exception::create(
        'InvalidParameter',
        'The scan type “[_1]” is disabled for this account.',
        [$scan_type]
    );

    return 1;
}

sub _get_pid_handler ($self) {
    return $self->{_pid_handler} if $self->{_pid_handler};

    require Cpanel::PID;
    $self->{_pid_handler} = Cpanel::PID->new( { pid_file => $self->{pid_file} } );
    return $self->{_pid_handler};
}

sub _get_clam_handler ($self) {
    return $self->{_clam_handler} if $self->{_clam_handler};

    my $port = ClamScanner_getsocket();

    require File::Scan::ClamAV;
    $self->{_clam_handler} = File::Scan::ClamAV->new( find_all => 1, port => $port );

    return $self->{_clam_handler} if $self->{_clam_handler}->ping();

    die Cpanel::Exception::create(
        'ConnectionFailed',
        'The system failed to connect to the “[_1]” service',
        ['ClamAV®'],
    );
}

sub _scan_file_is_old ($self) {
    my $now = time();
    return ( ( ( ( stat( $self->{'virus_file'} ) )[9] // 0 ) + 600 ) <= $now ? 1 : 0 );
}

sub _scan_is_running ($self) {
    my $pid_handler = $self->_get_pid_handler();

    my $current_pid = $pid_handler->get_current_pid();
    return 0 if !$current_pid;

    return $pid_handler->is_pid_running($current_pid);
}

sub _clean_pid_file ($self) {
    unlink $self->{pid_file} or die Cpanel::Exception::create(
        'IO::UnlinkError',
        'The system could not remove the “[_1]” file: [_2]',
        [ $self->{pid_file}, $! ],
    );
    return 1;
}

sub _clean_virus_file ($self) {
    my $num_virus  = scalar @{ $self->{'status_data'}{'infected_files'} };
    my $virus_file = $self->{'virus_file'};

    if ( $num_virus == 0 ) {
        if ( -s $virus_file ) {
            my $msg = "ClamScanner virus file should be deleted, but it's not empty: $virus_file";
            die Cpanel::Exception->create_raw($msg);
        }
        else {
            unlink $virus_file or die Cpanel::Exception::create(
                'IO::UnlinkError',
                'The system could not remove the “[_1]” file: [_2]',
                [ $virus_file, $! ],
            );
        }
    }

    return 1;
}

sub _create_pid_file ( $self, $pid ) {
    die 'provide pid' if !$pid;
    return $self->_get_pid_handler()->create_pid_file($pid);
}

sub _reset_status ($self) {
    $self->{status_data} = {
        current_file        => '',       #Current file being scanned
        total_file_count    => 0,        #Total file count
        scanned_file_count  => 0,        #Scanned file count
        total_file_size_MiB => 0,        #Total file size in MB
        scanned_file_size   => 0,        #Scanned file size in MB
        time_started        => time(),
        scan_complete       => 0,        #Is the scan complete
        infected_files      => [],       #List of infected files
    };

    return;
}

sub _update_status ( $self, %updated_data ) {
    $self->{status_data} = {
        %{ $self->{status_data} },
        %updated_data,
    };

    return;
}

sub _add_infected_file ( $self, $infected_file_path ) {
    push @{ $self->{status_data}{'infected_files'} }, $infected_file_path;

    return;
}

sub _write_status ($self) {

    my @expected_keys = qw/
      current_file
      total_file_count
      scanned_file_count
      total_file_size_MiB
      scanned_file_size
      time_started
      scan_complete
      infected_files
      /;

    for my $key (@expected_keys) {
        die "$key not found" unless exists $self->{status_data}{$key};
    }

    Cpanel::JSON::DumpFile( $self->{status_file}, $self->{status_data} );

    return;
}

1;
