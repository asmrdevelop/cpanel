package Cpanel::Form;

# cpanel - Cpanel/Form.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

# MEMORY!
#  Do not load Cpanel () from this module as it
#  does not required it most of the time and it will
#  always already be loaded if it does
#
#  use Cpanel                            ();
#
use Cpanel::IxHash                    ();
use Cpanel::Encoder::Tiny             ();
use Cpanel::TimeHiRes                 ();
use Cpanel::Buffer                    ();
use Cpanel::HTTP::QueryString::Legacy ();
use Cpanel::SV                        ();

use Cpanel::Imports;

my $logger;

our @EXPORT      = qw( parseform gettmpfile escapehtml getranddata );
our %EXPORT_TAGS = ( 'noquota' => [] );
our $VERSION     = '1.6';

our $file_uploads_allowed = 1;
our $Parsed_Form_hr;

our $read_buffer_size = $Cpanel::Buffer::DEFAULT_READ_SIZE;    # 2**17 is faster, but it makes upload progress updates too infrequent.
our $read_timeout     = 360;
our $MAX_FILE_SIZE    = 2199023255552;                         # Two Terabytes -- this used to be 2 Gigabytes, however that was Linux 2.4 days

my $ticks_per_second;

sub getranddata {
    _load_module_light('Cpanel::Rand');

    no warnings 'redefine';
    *getranddata = 'Cpanel::Rand'->can('getranddata');    # PPI NO PARSE -- module loaded with _load_module_light
    goto &getranddata;
}
*cleanfield = *Cpanel::Encoder::Tiny::safe_html_encode_str;

sub import {
    @_ = grep( !/:noquota/, @_ );
    if ($#_) {
        _load_module_light('Exporter');
        eval { goto \&Exporter::import; };
        die "Failed to import: $@";
    }                                                     # first item is the pkg, if there is anything else we need to import

    return;
}

sub parseform {    ##no critic qw(ProhibitExcessComplexity) -- requires scrum to fix
    my ( $fh, $cleanhtml, $formdatafh, $saveformdata ) = @_;
    my %FORM;
    my ( $trackupload, $multipart, $name, $buffer, $file_size_begin, $file_bytes_uploaded, $formdata, $tracker_fh, $file_upload_must_leave_bytes, $file_upload_max_bytes, $space_left, $new_space_left, $skip_upload, $homedir, $part_end_ticks, $bps );

    if ( $ENV{'CONTENT_LENGTH'} && $ENV{'CONTENT_LENGTH'} > 1 ) {
        tie %FORM, 'Cpanel::IxHash';
        my $orig_alarm   = alarm($read_timeout);
        my $current_time = time();
        my $start_time   = $current_time;
        my $end_time     = 0;
        if ( $orig_alarm > 0 ) {
            $end_time = $start_time + $orig_alarm;
            if ( $orig_alarm < $read_timeout ) {
                alarm($orig_alarm);
            }
        }

        $fh = \*STDIN if ( !defined($fh) || $fh eq '-1' );

        # select( ( select(STDERR), $| = 1 )[0] );    #aka STDERR->autoflush(1);

        my $content_length = int( $ENV{'CONTENT_LENGTH'} );

        #syswrite(STDERR, "[has content - length] = $content_length\n");

        $current_time = time();
        alarm( ( $end_time && ( $end_time - $current_time < $read_timeout ) ) ? ( $end_time - $current_time ) : $read_timeout );

        my $bytes_to_read    = $content_length < $read_buffer_size ? $content_length : $read_buffer_size;
        my $total_bytes_read = read( $fh, $formdata, $bytes_to_read ) || 0;

        #See case 55953 for why this is necessary.
        while ( $total_bytes_read < $bytes_to_read ) {
            my $bytes2 = read( $fh, $formdata, $bytes_to_read - $total_bytes_read, length $formdata );
            last if $bytes2 <= 0;
            $total_bytes_read += $bytes2;
        }

        #print STDERR "[formdata] = $formdata\n";

        local $Cpanel::CPDATA{'DEMO'} ||= q{};                                                             ## no critic qw(Variables::ProhibitAugmentedAssignmentInDeclaration) -- PPI NO PARSE - Only include Cpanel() when some other module uses it
        my $can_upload_files = ( ( $Cpanel::CPDATA{'DEMO'} ne '1' ) && $file_uploads_allowed ) ? 1 : 0;    # PPI NO PARSE - Only include Cpanel() when some other module uses it

        #syswrite(STDERR, "CAN_UPLOAD_FILES = $can_upload_files\n");

        if ( $formdata =~ /(.+)\r\n/ ) {
            $multipart = 1;

            #syswrite(STDERR, "[mult part is yes]\n");

            my $bound                     = $1;
            my $last_tracker_update_bytes = 0;

            #multiline mode
            my $type;
            my $part_start_ticks = [ Cpanel::TimeHiRes::gettimeofday() ];
            my $multipart_reader = Cpanel::Form::MultiPartReader->new( 'read_timeout' => $Cpanel::Form::read_timeout, 'formdata' => $formdata, 'fh' => $fh, 'bound' => $bound, 'content_length' => $content_length, 'read_buffer_size' => $Cpanel::Form::read_buffer_size, 'end_time' => $end_time );
            my ( $tmpfile, $tmpfh );

            $formdata         = '';    # will get refilled below
            $total_bytes_read = 0;

            while ( $multipart_reader->has_bytes_left() ) {

                #syswrite(STDERR, "[multi byte loop]\n");
                if ( $multipart_reader->{'inheaders'} ) {

                    $name = undef;
                    $type = 'skipped';

                    #syswrite(STDERR, "[multi byte loop] : inheaders=1\n");

                    $total_bytes_read += length( $buffer = $multipart_reader->readline("\r\n\r\n") );

                    print {$formdatafh} $buffer if ref $formdatafh;
                    if ($saveformdata) { $formdata .= $buffer; }

                    #syswrite( STDERR ,"[headers buffer] $buffer\n");
                    if ( $buffer =~ /filename=\"([^\"]+)\"/ ) {
                        if ($can_upload_files) {
                            $name = $1;
                            $name =~ s/\".*$//;
                            $type = 'file';
                            ( $tmpfile, $tmpfh ) = gettmpfile($homedir);
                            Cpanel::SV::untaint($tmpfile);

                            $name = _get_available_name_for_file( $name, \%FORM );

                            my ($key) = $buffer =~ /name=\"([^\"]+)\"/;
                            $FORM{"file-${name}-key"} = $key;
                            $FORM{"file-${name}"}     = $tmpfile;

                            print {$tracker_fh} "  <file name=\"", Cpanel::Encoder::Tiny::safe_xml_encode_str($name), "\" tmpfile=\"$tmpfile\">\n" if $trackupload;

                            # Disk usage restrictions
                            if ( !defined $file_upload_must_leave_bytes || !defined $file_upload_max_bytes ) {
                                ( $file_upload_must_leave_bytes, $file_upload_max_bytes ) = _get_max_upload();
                            }
                            $space_left ||= _calc_space_left();
                            $skip_upload = 0;
                        }
                    }
                    elsif ( my ($v) = $buffer =~ /name=\"(.+)\"/ ) {
                        $v = _get_available_name_for_value( $v, \%FORM );
                        if ( $v !~ /^file-/ ) {
                            $name = $v;
                            $type = 'value';
                        }
                    }

                    $multipart_reader->{'inheaders'} = 0;

                    $file_size_begin = $total_bytes_read if $type eq 'file';

                }
                elsif ( $multipart_reader->{'end_of_part'} ) {

                    #syswrite(STDERR, "[multi byte loop] : end_of_part=1\n");
                    $file_size_begin ||= 0;
                    my $actual_file_size = ( $total_bytes_read - $file_size_begin ) - 2;    #\r\n is not counted

                    $total_bytes_read += length( $buffer = $multipart_reader->next_part() );
                    print {$formdatafh} $buffer if ref $formdatafh;
                    if ($saveformdata) { $formdata .= $buffer; }

                    $type ||= q{};

                    if ( $type eq 'file' ) {
                        if ($can_upload_files) {
                            print {$tracker_fh} "    <progress filesize=\"$actual_file_size\" complete=\"1\"></progress>\n  </file>\n" if $trackupload;
                            close($tmpfh);
                            $space_left -= $file_bytes_uploaded;
                            if ($trackupload) {
                                print {$tracker_fh} "</fileupload>\n";
                                close($tracker_fh);
                            }
                        }
                    }
                    elsif ( $type eq 'value' ) {
                        $FORM{$name} =~ s/\r\n$//;

                        # Disallow this for privileged processes to prevent them
                        # from being the victim of a symlink attack.
                        if ( $name eq 'cpanel-trackupload' && $> != 0 && $can_upload_files ) {
                            $homedir ||= _gethomedir();
                            if ( !-d "$homedir/.cpanel" ) {
                                if ( !mkdir( "$homedir/.cpanel", 0700 ) ) {
                                    _logger()->warn( 'Could not create dir "' . "$homedir/.cpanel" . '"' );
                                }
                            }
                            $FORM{$name} =~ s/\///g;
                            open( $tracker_fh, '>', "$homedir/.cpanel/fileupload-$FORM{$name}.log" );
                            select( ( select($tracker_fh), $| = 1 )[0] );    #aka $tracker_fh->autoflush(1);
                            $trackupload = 1;
                            print {$tracker_fh} "<fileupload size=\"$content_length\">\n";
                        }
                    }
                }
                else {    # aka body
                          #syswrite(STDERR, "[multi byte loop] : body=1\n");
                    $total_bytes_read += length( $buffer = $multipart_reader->read_part() );
                    print {$formdatafh} $buffer if ref $formdatafh;
                    if ($saveformdata) { $formdata .= $buffer; }

                    if ( $multipart_reader->{'end_of_part'} ) {

                        #print STDERR "[end of part] [$buffer]\n";
                        substr( $buffer, -2, 2, '' );

                        #print STDERR "[end of part] [$buffer]\n";
                        # strip \r\n
                    }

                    # we are in the body
                    # if its a file save it to the temp file
                    # if not store it in memory
                    #syswrite(STDERR, "[multi byte read body] : " . length($buffer) . "\n");

                    if ( $type eq 'file' ) {
                        next if ( $skip_upload || !$can_upload_files );
                        $new_space_left = $space_left - ( $file_bytes_uploaded = ( $total_bytes_read - $file_size_begin ) );
                        if ( $new_space_left < $file_upload_must_leave_bytes ) {
                            _log_info_with_user("insufficient space for $name upload. Required space remaining after upload: $file_upload_must_leave_bytes, Remaining space before upload: $space_left");
                            if ( $FORM{"file-$name"} ) {
                                if ( -e $FORM{"file-$name"} ) {
                                    close($tmpfh);
                                    unlink $FORM{"file-$name"};
                                }

                                _add_form_error(
                                    \%FORM,
                                    locale()->maketext(
                                        q{Insufficient disk space for “[_1]” upload. Remaining space before upload: [format_bytes,_2], must be [format_bytes,_3] or more.},
                                        $name, $space_left, $file_upload_must_leave_bytes
                                    )
                                );
                                delete @FORM{ "file-$name", "file-$name-key" };
                            }
                            $skip_upload         = 1;
                            $file_bytes_uploaded = 0;
                            print {$tracker_fh} "    <error failreason=\"outofspace\" failmsg=\"insufficient space for $name upload. Required space remaining after upload: $file_upload_must_leave_bytes Remaining space before upload: $space_left\"></error>\n" if $trackupload;

                        }
                        elsif ( $file_bytes_uploaded > $file_upload_max_bytes ) {
                            _log_info_with_user("$name upload restricted due to size.");
                            if ( $FORM{"file-$name"} ) {
                                if ( -e $FORM{"file-$name"} ) {
                                    close($tmpfh);
                                    unlink $FORM{"file-$name"};
                                }
                                _add_form_error( \%FORM, locale()->maketext( "The system restricted the upload of “[_1]” due to its size.", $name ) );
                                delete @FORM{ "file-$name", "file-$name-key" };
                            }
                            $skip_upload         = 1;
                            $file_bytes_uploaded = 0;
                            print {$tracker_fh} "    <error failreason=\"uploadsize\" failmsg=\"upload restricted due to size.\"></error>\n" if $trackupload;
                        }
                        elsif ( $multipart_reader->early_eof ) {
                            _log_info_with_user("$name upload failed due to EOF.");
                            if ( $FORM{"file-$name"} ) {
                                if ( -e $FORM{"file-$name"} ) {
                                    close($tmpfh);
                                    unlink $FORM{"file-$name"};
                                }
                                _add_form_error( \%FORM, locale()->maketext( "The system’s upload of “[_1]” failed unexpectedly. Retry the upload, or contact your hosting provider.", $name ) );
                                delete @FORM{ "file-$name", "file-$name-key" };
                            }
                            $skip_upload         = 1;
                            $file_bytes_uploaded = 0;
                            print {$tracker_fh} "    <error failreason=\"uploadsize\" failmsg=\"upload failed due to EOF.\"></error>\n" if $trackupload;
                        }
                        elsif ( defined $buffer ) {
                            print {$tmpfh} $buffer;
                            if ($trackupload) {
                                $part_end_ticks = [ Cpanel::TimeHiRes::gettimeofday() ];
                                my $time_el = ( ( ( $part_end_ticks->[0] - $part_start_ticks->[0] ) + ( ( $part_end_ticks->[1] - $part_start_ticks->[1] ) / 1_000_000 ) ) + 0.0001 );

                                # my $telap    = ( ( $part_end_ticks - $part_start_ticks ) / $ticks_per_second ) + 0.0001;
                                # my $bps      = sprintf( '%.2f', ( $bytes_since_last_tracker_update / $telap ) );
                                $bps                                    = sprintf( '%.2f', ( ( $total_bytes_read - $last_tracker_update_bytes ) / ( ( ( $part_end_ticks->[0] - $part_start_ticks->[0] ) + ( ( $part_end_ticks->[1] - $part_start_ticks->[1] ) / 1_000_000 ) ) + 0.0001 ) ) );
                                $multipart_reader->{'read_buffer_size'} = $bps > 2097120 ? 2097120 : $bps > 1048560 ? 1048560 : $bps >= 524280 ? 524280 : $bps >= 262140 ? 262140 : $bps >= 131070 ? 131070 : 65535;
                                $multipart_reader->{'read_timeout'}     = $bps > 131070  ? 720     : 360;
                                print {$tracker_fh} "    <progress bytes=\"$file_bytes_uploaded\" bps=\"$bps\"></progress>\n" if $last_tracker_update_bytes;
                                $last_tracker_update_bytes = $total_bytes_read;
                                $part_start_ticks          = $part_end_ticks;
                            }
                        }

                    }
                    elsif ( $type eq 'value' ) {

                        #print STDERR "[read_block] $buffer\n";
                        $FORM{$name} .= $buffer;
                    }
                }
            }

            my $fileno_tmpfh = $tmpfh && fileno $tmpfh;
            if ( $fileno_tmpfh && int($fileno_tmpfh) > 0 ) {
                $space_left -= $file_bytes_uploaded;
                close($tmpfh);
                print {$tracker_fh} "    <progress complete=\"1\"></progress>\n  </file>\n" if $trackupload;
            }
            if ( $trackupload && $tracker_fh && defined fileno $tracker_fh ) {
                print {$tracker_fh} "</fileupload>\n";
                close($tracker_fh);
            }
        }
        else {
            my $bytes_read;

            # straight content_length read
            while ( $bytes_to_read = ( $content_length - $total_bytes_read ) ) {
                $current_time = time();
                alarm( ( $end_time && ( $end_time - $current_time < $read_timeout ) ) ? ( $end_time - $current_time ) : $read_timeout );
                $total_bytes_read += ( $bytes_read = read( $fh, $formdata, $bytes_to_read, length $formdata ) );
                last if !$bytes_read;
            }
            print {$formdatafh} $formdata if ref $formdatafh;
        }

        # Restore the original alarm.  If we went over for some reason while processing the form we'll give one additional second.
        $current_time = time();
        my $new_alarm = ( $end_time && $end_time - $current_time > 0 ) ? ( $end_time - $current_time ) : $end_time ? 1 : 0;
        alarm($new_alarm);

    }

    my @total_query_parts = (
        ( $ENV{'QUERY_STRING'}     ? \$ENV{'QUERY_STRING'} : () ),
        ( !$multipart && $formdata ? \$formdata            : () ),
    );
    my $total_query = join( '&', map { $$_ } @total_query_parts );

    if ( length $total_query ) {
        my $parsed_query_hr = Cpanel::HTTP::QueryString::Legacy::legacy_parse_query_string_sr( \$total_query );
        if ( my @keys = keys %$parsed_query_hr ) {

            #We have to tie() even if there is only one hash member because
            #Cpanel::IxHash does encoding as well as ordering; even if the
            #ordering isn’t needed, we still need the encoding.
            tie %FORM, 'Cpanel::IxHash' if !tied %FORM && %$parsed_query_hr;

            #SECURITY: Reject any keys that match m{\Afile-} because this can allow
            #arbitrary filesystem access. This must be done AFTER the URI-decode
            #so that we catch URI-encoded "file-".
            if ( delete @{$parsed_query_hr}{ grep { index( $_, 'file-' ) == 0 } @keys } ) {

                # If we deleted a key we need to enumerate the keys again
                @FORM{ keys %$parsed_query_hr } = values %$parsed_query_hr;
            }
            else {
                # No change in @keys so we can just use all the values
                @FORM{@keys} = values %$parsed_query_hr;
            }
        }
    }

    #This should really be done outside this module. It's only used in one
    #place locally, but 3rd-party code might depend on its being here.
    if ($cleanhtml) {
        %FORM = html_encode_form( \%FORM );
    }

    $Parsed_Form_hr = \%FORM;

    if ($saveformdata) { return ( \%FORM, $formdata ); }

    return wantarray ? %FORM : \%FORM;
}

sub html_encode_form {
    my ($form_hr) = @_;
    my $key;
    my @newform;
    for $key ( keys %$form_hr ) {
        push @newform, ( Cpanel::Encoder::Tiny::safe_html_encode_str($key) => Cpanel::Encoder::Tiny::safe_html_encode_str( $form_hr->{$key} ) );
    }
    return @newform;
}

# _load_module_light is to avoid
# bringing in Cpanel::LoadModule and thus Cpanel::Exception
sub _load_module_light {
    my ($module) = @_;

    local $@;
    eval "require $module" or die "Failed to load the perl module “$module”: $@";

    return;
}

sub _get_max_upload {
    _load_module_light('Cpanel::Config::LoadCpConf');
    my $cpconf = ( tied %Cpanel::CONF || scalar keys %Cpanel::CONF ) ? \%Cpanel::CONF : 'Cpanel::Config::LoadCpConf'->can('loadcpconf_not_copy')->();    # PPI NO PARSE -- check earlier - safe since we do not modify

    my ( $file_upload_max_bytes, $file_upload_must_leave_bytes );

    if ( exists $cpconf->{'file_upload_must_leave_bytes'} && $cpconf->{'file_upload_must_leave_bytes'} ne '' ) {
        $file_upload_must_leave_bytes = $cpconf->{'file_upload_must_leave_bytes'} eq 'unlimited' ? 0 : int( $cpconf->{'file_upload_must_leave_bytes'} );
        $file_upload_must_leave_bytes = ( $file_upload_must_leave_bytes * 1024 * 1024 );
    }
    else {
        $file_upload_must_leave_bytes = 5242880;
    }

    if ( $file_upload_must_leave_bytes > ( 1024 * 1024 * 1024 * 10 ) ) {                                                                                 #must be below ten gigs
        $file_upload_must_leave_bytes = 5242880;
    }

    if ( length $cpconf->{'file_upload_max_bytes'} ) {
        $file_upload_max_bytes = $cpconf->{'file_upload_max_bytes'} eq 'unlimited' ? 999999999999999 : int( $cpconf->{'file_upload_max_bytes'} );
        $file_upload_max_bytes = ( $file_upload_max_bytes * 1024 * 1024 );
    }
    else {
        $file_upload_max_bytes = 99999999999999;
    }

    return ( $file_upload_must_leave_bytes, $file_upload_max_bytes );
}

# return tmp dir in user's home dir or /tmp if $Cpanel::homedir not defined
sub gettmpfile {
    my $homedir = shift || _gethomedir();
    _load_module_light('Cpanel::Rand');
    if ( !-d $homedir . '/tmp' ) { mkdir( $homedir . '/tmp', 0755 ); }
    return 'Cpanel::Rand'->can('get_tmp_file_by_name')->( $homedir . '/tmp/Cpanel_Form_file', '.upload' );    # PPI NO PARSE -- loaded earlier - audit case 46806 ok
}

sub _log_info_with_user {
    my ($msg) = @_;
    my $user = _get_username();
    _logger()->info("User $user, $msg");
    return;
}

sub _get_username {
    my $user = $Cpanel::user;                                                                                 # PPI NO PARSE - Only include Cpanel() when some other module uses it
    if ( !$user ) {

        # We don't want to use the cache unless it is already loaded
        if ( $INC{'Cpanel/PwCache.pm'} ) {
            $user = Cpanel::PwCache::getusername();
        }
        else {
            $user = getpwuid($>);
        }
    }
    return $user;
}

sub _gethomedir {
    my $accthomedir = shift;
    my $homedir     = $Cpanel::homedir || $accthomedir || '';    # PPI NO PARSE - Only include Cpanel() when some other module uses it
    if ( !$homedir ) {
        if ( $INC{'Cpanel/PwCache.pm'} ) {
            return Cpanel::PwCache::gethomedir();
        }
        my $euid_home = ( getpwuid($>) )[7];
        $homedir = $euid_home || '';
    }

    return $homedir;
}

sub _calc_space_left {
    my $space_left;
    if ( $> != 0 ) {
        try {
            _load_module_light('Cpanel::Quota') if !$INC{'Cpanel/Quota.pm'};
        }
        catch { warn $_ };

        return $MAX_FILE_SIZE if !$INC{'Cpanel/Quota.pm'};

        # 0 = DISK USED
        # 1 = DISK LIMIT
        # 2 = DISK REMAIN
        # 3 = FILES USED
        # 4 = FILES LIMIT
        # 5 = FILES REMAIN
        my @quota = 'Cpanel::Quota'->can('displayquota')->();    # PPI NO PARSE -- loaded with _load_module_light

        return $MAX_FILE_SIZE if $quota[0] eq $Cpanel::Quota::QUOTA_NOT_ENABLED_STRING;

        my $calc_space_left = $quota[2];
        if ( $calc_space_left =~ m/^\-?\d+(?:\.\d+)?$/ ) {
            $space_left = ( $calc_space_left * 1024 * 1024 );

            # Case CPANEL-2775: If the user has no quota set (unlimited), then
            # we'll want to return the MAX_FILE_SIZE value here
            # to ensure that file uploads are allowed properly.
            return $MAX_FILE_SIZE if ( $space_left > $MAX_FILE_SIZE ) || ( $quota[1] == 0 );
            return $space_left;
        }
        else {
            return $MAX_FILE_SIZE;
        }
    }
    return $MAX_FILE_SIZE;
}

sub _add_form_error {
    my ( $form, $error ) = @_;

    die "Require form ref as first arg" unless ref($form) eq 'HASH';

    push @{ $form->{_ERRORS_} }, $error;
    return $error;
}

sub get_errors {
    my $form = $_[0] || $Parsed_Form_hr;

    return @{ $form->{_ERRORS_} || [] };
}

sub _get_available_name_for_value {
    my ( $name, $form ) = @_;

    $name =~ s/\".*$//g;
    my ( $c, $dash ) = ( '', '' );
    while ( exists $form->{ $name . $dash . $c } ) {
        $dash ||= '-';
        $c eq '' ? $c = 0 : ++$c;
    }
    return join( '', $name, $dash, $c );
}

sub _get_available_name_for_file {
    my ( $name, $form ) = @_;

    # get file extension + remove it from name
    my @names = split( '\.', $name );
    my $ext   = scalar @names > 1 ? '.' . pop(@names) : '';
    $name = join( '.', @names );

    my ( $counter, $dash, $candidate ) = ( '', '' );

    # loop while we have not find an available name
    while ( $candidate = "${name}${dash}${counter}${ext}" ) {

        # both names need to be available
        last if !exists $form->{ 'file-' . $candidate } && !exists $form->{ 'file-' . $candidate . '-key' };

        # start at 2
        $counter eq '' ? $counter = 2 : ++$counter;
        $dash ||= '-';
    }

    return $candidate;
}

# Get the filename if the item is a Cpanel::Form parse file.
# Returns the file name if it was or an empty list otherwise.
sub _get_file_name {
    my ( $form, $item ) = @_;
    return $item =~ m{\Afile-(.*)-key\z}s && exists $form->{"file-$1"} ? $1 : ();
}

# Returns 1 if there are file uploads, 0 otherwise.
sub has_uploaded_files {
    my $form = shift || $Parsed_Form_hr;
    require Cpanel::ArrayFunc;
    my $found = Cpanel::ArrayFunc::first( sub { _get_file_name( $form, $_ ) }, keys %$form );
    return $found ? 1 : 0;
}

#Returns a array ref of { filename: "..", formname: ".." }
sub get_uploaded_files_ar {
    my $form = shift || $Parsed_Form_hr;

    local $Cpanel::IxHash::Modify = 'none';

    my @filenames = map { _get_file_name( $form, $_ ) } keys %$form;

    return [ map { { filename => $_, formname => $form->{"file-$_-key"}, temppath => $form->{"file-$_"} } } @filenames ];
}

sub get_upload_name_and_path {
    my ( $formname, $form ) = @_;

    $form ||= $Parsed_Form_hr;

    my ( $formkey, $k, $v );
    while ( ( $k, $v ) = each %$form ) {
        if ( $v eq $formname && $k =~ /\Afile-(.*)-key\z/s ) {
            my $uploadname = $1;

            keys %$form;    #reset the hash pointer

            return ( $uploadname, $form->{"file-$uploadname"} );
        }
    }
    return;
}

#NOTE: Try to avoid using this function; instead, prefer
#open_uploaded_file.
sub get_uploaded_file_temp_path {
    my ( $formname, $form ) = @_;
    return ( get_upload_name_and_path( $formname, $form ) )[1];
}

#Pass in the variable name by which the file was sent in the form.
#Even though internally we "index" by the filename, the variable name
#makes a more sensible "key".
sub open_uploaded_file {
    my ( $formname, $form ) = @_;
    return if !defined $formname;

    my $tmpfile = get_uploaded_file_temp_path( $formname, $form );
    return if !$tmpfile;

    if ( open my $fh, '<', $tmpfile ) {
        return $fh;
    }

    return;
}

sub _logger {
    return $logger if defined $logger;
    _load_module_light('Cpanel::Logger');
    return ( $logger = 'Cpanel::Logger'->new() );    # PPI NO PARSE - loaded with _load_module_light
}

package Cpanel::Form::MultiPartReader;

our $MAX_CONTENT_SIZE = ( 1024 * 1024 * 1024 * 1024 );

sub new {
    my $class = shift;
    my %OPTS  = @_;

    my $self = {};
    bless $self;

    $self->{'formdata'}           = $OPTS{'formdata'} || '';                                   # Only used if we have already read from an file handle and need to fill the object
    $self->{'fh'}                 = $OPTS{'fh'};
    $self->{'inheaders'}          = 0;
    $self->{'bound'}              = $OPTS{'bound'};
    $self->{'bound_regex'}        = qr/\Q$self->{'bound'}\E/;
    $self->{'content_length'}     = $OPTS{'content_length'};
    $self->{'read_buffer_size'}   = $OPTS{'read_buffer_size'} || die "Buffer size required";
    $self->{'bytes_left_to_read'} = $self->{'content_length'} - length $self->{'formdata'};
    $self->{'read_timeout'}       = $OPTS{'read_timeout'} || $Cpanel::Form::read_timeout;
    $self->{'end_of_part'}        = 1;

    #$self->{'bytes_left_to_read'} = $MAX_CONTENT_SIZE;
    $self->{'content_length'} -= length $self->{'formdata'};
    $self->{'bytes_read'} = 0;

    if ( !$self->{'bound'} ) {
        _logger()->panic("Cpanel::Form::MultiPartReader requires a boundary (bound setting)");
    }
    if ( !$self->{'fh'} ) {
        _logger()->panic("Cpanel::Form::MultiPartReader requires a file descriptor to read from (fh setting)");
    }

    return $self;
}

sub has_bytes_left {
    my $self = shift;

    #my $fl = length($self->{'formdata'});
    #syswrite(STDERR, "[has_bytes_left]     ( $self->{'bytes_left_to_read'} > 0 || $fl )\n");

    ( $self->{'bytes_left_to_read'} || length $self->{'formdata'} ) ? 1 : 0;
}

sub early_eof {
    my $self = shift;
    return $self->{'early_eof'};
}

sub readline {
    my $self                   = shift;
    my $input_record_separator = shift || "\n";

    if ( ( $self->{'last_match_position'} = index( $self->{'formdata'}, $input_record_separator ) ) != -1 ) {
        return substr( $self->{'formdata'}, 0, ( $self->{'last_match_position'} + length($input_record_separator) ), '' );
    }

    while ( $self->{'last_match_position'} == -1 && $self->{'bytes_left_to_read'} > 0 ) {

        $self->{'current_time'} = time();
        alarm( ( $self->{'end_time'} && ( $self->{'end_time'} - $self->{'current_time'} < $self->{'read_timeout'} ) ) ? ( $self->{'end_time'} - $self->{'current_time'} ) : $self->{'read_timeout'} );

        $self->{'bytes_left_to_read'} -= ( $self->{'bytes_read'} = read( $self->{'fh'}, $self->{'formdata'}, $self->{'bytes_left_to_read'} > $self->{'read_buffer_size'} ? $self->{'read_buffer_size'} : $self->{'bytes_left_to_read'}, length( $self->{'formdata'} ) ) );

        $self->{'last_match_position'} = index( $self->{'formdata'}, $input_record_separator );

        #syswrite( STDERR, "Read: $self->{'bytes_read'} bytes from readline\n" );
        if ( !$self->{'bytes_read'} ) {    # READ FAILURE
            $self->{'early_eof'}          = 1 if $self->{'bytes_left_to_read'};
            $self->{'bytes_left_to_read'} = 0;
            last;
        }

    }

    substr( $self->{'formdata'}, 0, ( $self->{'last_match_position'} == -1 ? length( $self->{'formdata'} ) : ( $self->{'last_match_position'} + length($input_record_separator) ) ), '' );    # includes the \n
}

sub read_part {
    my $self = shift;

    while ( ( $self->{'does_not_match_bound_regex'} = ( $self->{'formdata'} !~ $self->{'bound_regex'} ) ? 1 : 0 ) && length $self->{'formdata'} < $self->{'read_buffer_size'} && $self->{'bytes_left_to_read'} > 0 ) {
        $self->{'current_time'} = time();
        alarm( ( $self->{'end_time'} && ( $self->{'end_time'} - $self->{'current_time'} < $self->{'read_timeout'} ) ) ? ( $self->{'end_time'} - $self->{'current_time'} ) : $self->{'read_timeout'} );

        $self->{'bytes_left_to_read'} -= ( $self->{'bytes_read'} = read( $self->{'fh'}, $self->{'formdata'}, $self->{'bytes_left_to_read'} > $self->{'read_buffer_size'} ? $self->{'read_buffer_size'} : $self->{'bytes_left_to_read'}, length( $self->{'formdata'} ) ) );

        if ( !$self->{'bytes_read'} ) {    # READ FAILURE
            $self->{'early_eof'}                  = 1 if $self->{'bytes_left_to_read'};
            $self->{'bytes_left_to_read'}         = 0;
            $self->{'end_of_part'}                = 1;
            $self->{'does_not_match_bound_regex'} = ( $self->{'formdata'} !~ $self->{'bound_regex'} ) ? 1 : 0;
            last;
        }
    }

    if ( $self->{'does_not_match_bound_regex'} ) {

        #syswrite(STDERR,"read_part flushing\n");
        $self->{'end_of_part'} = 1 if $self->{'bytes_left_to_read'} <= 0;

        return substr( $self->{'formdata'}, 0, length( $self->{'formdata'} ), '' );
    }
    else {

        #syswrite(STDERR,"read_part found end of part\n");
        $self->{'end_of_part'} = 1;
        return substr( $self->{'formdata'}, 0, index( $self->{'formdata'}, $self->{'bound'} ), '' );    # does not include the bound, and we do not return the \r\n
    }

}

sub next_part {
    my $self = shift;
    $self->{'end_of_part'} = 0;
    $self->{'inheaders'}   = 1;
    $self->readline();    # will send back the bound
}

1;
