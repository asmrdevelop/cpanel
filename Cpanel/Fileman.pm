package Cpanel::Fileman;

# cpanel - Cpanel/Fileman.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel           ();
use Cpanel::API      ();
use Cpanel::Binaries ();
use Cpanel::ClamScan ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Encoder::Tiny             ();
use Cpanel::Encoder::URI              ();
use Cpanel::Encoding                  ();
use Cpanel::Fileman::Mime             ();
use Cpanel::FileUtils::Copy           ();
use Cpanel::FileUtils::TouchFile      ();
use Cpanel::IxHash                    ();
use Cpanel::LoadModule                ();
use Cpanel::Locale                    ();
use Cpanel::Fcntl::Types              ();
use Cpanel::Logger                    ();
use Cpanel::PwCache::GID              ();
use Cpanel::Quota                     ();
use Cpanel::SafeDir                   ();
use Cpanel::SafeDir::MK               ();
use Cpanel::SafeFile                  ();
use Cpanel::SafeFile::Replace         ();
use Cpanel::SafeFind                  ();
use Cpanel::SafeRun::Dynamic          ();
use Cpanel::SafeRun::Errors           ();
use Cpanel::SafeRun::Simple           ();
use Cpanel::IONice                    ();
use Cpanel::Tar                       ();
use Cwd                               ();
use Fcntl                             ();
use IPC::Open3                        ();
use Cpanel::Binaries::Rpm             ();
use Cpanel::Binaries::Debian::DpkgDeb ();

use Errno qw[EISDIR ENOTEMPTY EEXIST];

use Cpanel::Server::Type::Role::FileStorage ();

our $VERSION = '1.5';

our $READ_BUFFER_SIZE = 131070;

our $FILE_BASE_PERMS = 0666;
our $DIR_BASE_PERMS  = 0777;

our $FILE_TEMPLATES_DIRECTORY = '/usr/local/cpanel/share/templates';

my $DIRECTORY_SEPARATOR = q{/};

my ( %SAFEDIRCACHE, $APIref, %SPECIAL_FILES, %MIME_IMAGES, $loaded_mimename_data );

my $logger = Cpanel::Logger->new();

sub listtemplates {
    return if _notallowed(1);

    if ( -d "$Cpanel::root/share/templates" ) {
        opendir( my $tmplt_dh, "$Cpanel::root/share/templates" )
          or $logger->die("Could not open $Cpanel::root/share/templates: $!");

        print qq{<option value="Text Document">Text Document</option>\n};

        for my $tmpl ( sort grep( !/^(\.|\.\.)$/, readdir $tmplt_dh ) ) {
            print qq{ <option value="$tmpl">$tmpl</option>\n};
        }
        closedir $tmplt_dh;
    }
    return;
}

## DEPRECATED!
sub api2_uploadfiles {

    # Takes the files that Cpanel::Form::parseform has already saved as
    # temp files in ~/tmp and renames them.

    my %OPTS = ( @_, 'api.quiet' => 1 );

    # Fix parameter name changes
    $OPTS{'get_disk_info'} = delete $OPTS{'getdiskinfo'};

    my $result = Cpanel::API::wrap_deprecated( 'Fileman', 'upload_files', \%OPTS );

    return @{ [ $result->data() ] || [] };
}

sub uploadfiles {
    return if _notallowed( 0, 1 );    #used so many places

    my $locale = Cpanel::Locale->get_handle();

    local $Cpanel::IxHash::Modify = 'none';

    my $dir =
      defined $Cpanel::FORM{'dir'}
      ? Cpanel::SafeDir::safedir( $Cpanel::FORM{'dir'} )
      : $Cpanel::abshomedir;

    if ( !-e $dir ) {
        Cpanel::SafeDir::MK::safemkdir($dir);
    }

    chdir $dir or $logger->die("Can not change into $dir: $!");

  FILE:
    foreach my $file ( sort keys %Cpanel::FORM ) {
        next FILE if $file =~ m/^file-(.*)-key$/;
        next FILE if $file !~ m/^file-(.*)/;

        my $thisdir  = $dir;
        my $origfile = $1;
        my $key      = $Cpanel::FORM{ ${file} . '-key' };
        if ( $Cpanel::FORM{ $key . '_relativePath' } ne '' ) {
            my $rp = $Cpanel::FORM{ $key . '_relativePath' };
            my @RP = split( m{/}, $rp );
            pop(@RP);
            $rp      = join( '/', @RP );
            $thisdir = Cpanel::SafeDir::safedir("$dir/$rp");
            Cpanel::SafeDir::MK::safemkdir($thisdir);
        }

        $Cpanel::FORM{$file} =~ s{\n}{}g;
        my @FTREE = split( /([\\\/])/, $origfile );
        my $fname = safefile( $FTREE[-1] );

        my $html_safe_origfile = Cpanel::Encoder::Tiny::safe_html_encode_str($origfile);
        my $html_safe_fname    = Cpanel::Encoder::Tiny::safe_html_encode_str($fname);
        my $html_safe_tmpfile  = Cpanel::Encoder::Tiny::safe_html_encode_str( $Cpanel::FORM{$file} );
        my $html_safe_thisdir  = Cpanel::Encoder::Tiny::safe_html_encode_str($thisdir);

        my $hasvirus = Cpanel::ClamScan::ClamScan_scan( $Cpanel::FORM{$file} );

        if (   $hasvirus ne ''
            && $hasvirus ne 'OK'
            && ( $hasvirus !~ m/access file/i && $hasvirus !~ m/no such/i ) ) {
            print "$html_safe_origfile ($html_safe_fname): <font color=#FF0000>Virus Detected; File not Uploaded! ($hasvirus)</font><br>\n";
            $logger->info("Virus detected in upload  $Cpanel::FORM{$file} by user $Cpanel::user ($origfile): $hasvirus");
            unlink $Cpanel::FORM{$file};
        }
        else {
            my $need_chmod;
            if ( !-e "$thisdir/$fname" ) {
                if ( rename $Cpanel::FORM{$file}, "$thisdir/$fname" ) {
                    chown( $<, $), "$thisdir/$fname" )
                      or print "chown $html_safe_thisdir/$html_safe_fname failed: $!<br />";
                }
                else {
                    print "move $html_safe_tmpfile to $html_safe_thisdir/$html_safe_fname failed: $!<br />";
                    $logger->info("Rename of $Cpanel::FORM{$file} to $thisdir/$fname failed: $!");
                }
                if ( -e "$thisdir/$fname" ) {
                    print $locale->maketext( 'Upload of “[_1]” ([_2]) succeeded.', $html_safe_origfile, $html_safe_fname ) . "<br />\n";
                    $need_chmod = 1;
                }
                else {
                    print $locale->maketext( 'Upload of “[_1]” ([_2]) failed.', $html_safe_origfile, $html_safe_fname ) . "<br />\n";
                }
            }
            else {
                if ( int( $Cpanel::FORM{'overwrite'} ) == 1 ) {

                    #rename() clobbers an existing file; there is
                    #no need to unlink() before rename().
                    if ( rename $Cpanel::FORM{$file}, "$thisdir/$fname" ) {
                        chown( $<, $), "$thisdir/$fname" )
                          or print "chown $html_safe_thisdir/$html_safe_fname failed: $!<br />";
                        print $locale->maketext( 'Upload of “[_1]” ([_2]) succeeded.', $html_safe_origfile, $html_safe_fname ) . ' ';
                        print $locale->maketext('The system overwrote the old file.') . "<br>\n";
                        $need_chmod = 1;
                    }
                    else {
                        print "move $html_safe_tmpfile to $html_safe_thisdir/$html_safe_fname failed: $!<br />";
                        print "move $html_safe_tmpfile to $html_safe_thisdir/$html_safe_fname failed: $!<br />";
                        $logger->info("Rename of $Cpanel::FORM{$file} to $thisdir/$fname failed: $!");
                    }
                }
                else {
                    print $locale->maketext( 'Could not move “[_1]” to “[_2]” because it already exists.', $html_safe_origfile, "$html_safe_thisdir/$html_safe_fname" ) . "<br>\n";
                }
            }

            if ($need_chmod) {
                my $perms = $Cpanel::FORM{'permissions'};
                if ( defined($perms) ) {
                    $perms = oct $perms;
                }
                else {
                    $perms = 0644;
                }
                chmod( $perms, "$thisdir/$fname" )
                  or print "chmod $html_safe_thisdir/$html_safe_fname (" . sprintf( '%04lo', $perms ) . ") failed: $!<br />";
            }
        }
        if ( -e $Cpanel::FORM{$file} ) {
            unlink $Cpanel::FORM{$file} or print "Could not remove $Cpanel::FORM{$file}<br />\n";
        }
    }
    return;
}

sub api2_getdir {

    #    $API{'getdiractions'}{'modify'} = 'none';
    my %CFG = @_;
    my @RSD;
    my $dir = $CFG{'dir'};
    $dir = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    my $up = int $CFG{'up'};
    if ( $up > 0 ) {
        my @DPATH = split( /\//, $dir );
        for ( my $i = 1; $i <= $up; $i++ ) {
            last if ( $#DPATH == -1 || $i > 64 );
            pop(@DPATH);
        }
        $dir = join( '/', @DPATH );
        if ( length($dir) < length($Cpanel::abshomedir) ) {
            $dir = $Cpanel::abshomedir;
        }
        else {
            $dir = Cpanel::SafeDir::safedir($dir);
        }
    }
    push( @RSD, { 'dir' => Cpanel::Encoder::URI::uri_encode_str($dir) } );
    return (@RSD);

}

## DEPRECATED!
sub api2_statfiles {
    my %OPTS = ( @_, 'api.quiet' => 1, 'include_user' => 1, 'include_group' => 1, 'include_mime' => 1, 'show_hidden' => 1 );

    # Fix parameter name changes
    my @files = split( /\|/, $OPTS{'files'} || '' );
    my $dir   = $OPTS{'dir'};
    $dir = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $OPTS{'stat_rules'} = 1;

    # No files passed, or one file passed and is the home directory
    if ( !@files || @files == 1 && $files[0] eq $Cpanel::abshomedir ) {
        shift(@files);
        my (@HR) = split( /\//, Cpanel::SafeDir::safedir($dir) );
        unshift( @files, pop(@HR) );
        $dir = join( '/', @HR );
    }

    $OPTS{'dir'} = $dir;
    if ( $#files != -1 ) {
        $OPTS{'limit_to_list'}    = 1;
        $OPTS{'only_these_files'} = \@files;
    }

    my $result    = Cpanel::API::wrap_deprecated( 'Fileman', 'list_files', \%OPTS );
    my $uapi_data = $result->data();
    my @data;

    # Transform the results to match expectations
    foreach my $file ( @{$uapi_data} ) {
        if ( $file->{'exists'} ) {
            $file->{'type'}     = 'special' if $file->{'type'} ne 'dir' && $file->{'type'} ne 'file';
            $file->{'mimeinfo'} = delete $file->{'mimetype'};
            push @data, $file;
        }
    }

    return @{ \@data || [] };
}

## DEPRECATED!
sub api2_listfiles {
    my %OPTS = ( @_, 'api.quiet' => 1 );

    # Fix parameter name changes
    if ( exists $OPTS{'filelist'} ) {
        $OPTS{'limit_to_list'} = delete $OPTS{'filelist'};
    }
    $OPTS{'include_mime'}               = delete $OPTS{'needmime'}     if exists $OPTS{'needmime'};
    $OPTS{'show_hidden'}                = delete $OPTS{'showdotfiles'} if exists $OPTS{'showdotfiles'};
    $OPTS{'check_for_leaf_directories'} = delete $OPTS{'checkleaf'}    if exists $OPTS{'checkleaf'};

    my $result = Cpanel::API::wrap_deprecated( 'Fileman', 'list_files', \%OPTS );
    return @{ $result->data() || [] };
}

sub api2_getpath {
    my %CFG = @_;
    my $dir = $CFG{'dir'};
    $dir = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    my $vdir = $dir;
    $vdir =~ s/^$Cpanel::abshomedir//g;
    $vdir =~ s/^\///g;

    my @DIRPART;
    my $tdir;
    foreach my $dirs ( split( /\//, $vdir ) ) {
        $tdir = $tdir . "$dirs/";
        push( @DIRPART, { 'dirurl' => "/$tdir", 'dirpart' => $dirs } );
    }
    my @RSD;
    push( @RSD, { 'dirparts' => \@DIRPART, 'dir' => $dir } );
    return @RSD;

}

sub listfiles {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::RequireArgUnpacking)
    return if _notallowed(1);

    my ( $dir, $chooser, $select, $dirselect, $usesameframe ) = @_;
    $select    = 'select.html' if Cpanel::Encoder::URI::uri_encode_str($select) eq '';
    $dirselect = 'seldir.html'
      if Cpanel::Encoder::URI::uri_encode_str($dirselect) eq '';
    $dir = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;

    my $locale = Cpanel::Locale->get_handle();

    if ( !-d $dir ) {
        print $locale->maketext( 'Internal error: can’t find that folder: [_1]', Cpanel::Encoder::Tiny::safe_html_encode_str($dir) ) . "\n";
        return;
    }

    $dir =~ s/\/$//g;

    my $html_safe_dir = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $uri_safe_dir  = Cpanel::Encoder::URI::uri_encode_str($dir);

    chdir $dir or do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    my $vdir = $dir;
    $vdir =~ s/^$Cpanel::abshomedir//g;
    $vdir =~ s/^\///g;

    mkdir "$Cpanel::abshomedir/.trash", 0700
      if !-e "$Cpanel::abshomedir/.trash";

    opendir my $pwd_dh, '.' or $logger->die("Could not open PWD: $!");
    my @DIRLS = grep( !/^\.$/, readdir $pwd_dh );    # onyl '.' will be excluded
    closedir $pwd_dh;

    print '<table width="100%">';
    my $file                 = '';
    my $uri_safe_file        = Cpanel::Encoder::URI::uri_encode_str($file);
    my $html_safe_file       = Cpanel::Encoder::Tiny::safe_html_encode_str($file);
    my $image                = 'httpd-unix-directory.png';
    my $html_safe_script_uri = Cpanel::Encoder::Tiny::safe_html_encode_str( $ENV{'SCRIPT_URI'} );

    if ( !$chooser ) {

        # ?? 2 opening a tags and onely one closing, nothing to actually be the link
        print qq(<tr><td><a href="$html_safe_script_uri?dir=$uri_safe_dir/$uri_safe_file"><img src="../mimeicons/$image" border="0"></a></td><td><a href="dofileop.html?dir=$uri_safe_dir/$uri_safe_file" target=infofr><a href="$html_safe_script_uri?dir=/">/</a>);
    }
    else {

        # ?? nothing to actually be the link
        print qq(<tr><td><a href="$html_safe_script_uri?dir=$uri_safe_dir/$uri_safe_file"><img src="../mimeicons/$image" border=0></a></td><td><a href=\"$html_safe_script_uri?dir=/\">/</a>);
    }
    my $tdir = '';
    foreach my $dirs ( split( /\//, $vdir ) ) {
        $tdir = $tdir . "$dirs/";
        my $uri_safe_tdir  = Cpanel::Encoder::URI::uri_encode_str($tdir);
        my $html_safe_dirs = Cpanel::Encoder::Tiny::safe_html_encode_str($dirs);
        print qq( <a href="$html_safe_script_uri?dir=/$uri_safe_tdir">$html_safe_dirs</a> / );
    }

    print " (Current Folder)</a>\n";
    print "</td><td></td><td></td></tr>\n ";

    if ( !$chooser ) {
        print qq(<tr><td><a target=infofr href="createdir.html"><img src="../mimeicons/$image" border="0"></a></td><td><a target="infofr" href="createdir.html?dir=$uri_safe_dir"><b>Create New Folder</b></a></td><td></td><td></td></tr>);
    }
    $image = 'up.gif';

    if ( !$chooser ) {
        print qq(<tr><td><center><a class=ajaxlink href="upload.html?dir=$uri_safe_dir"><img src="images/$image" border=0></a></td><td><a class="ajaxlink" href="upload.html?dir=$uri_safe_dir"><b>Upload file(s)</b></a></td><td></td><td></td></tr>);
    }

    foreach my $file ( sort @DIRLS ) {
        my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);
        my $uri_safe_file  = Cpanel::Encoder::URI::uri_encode_str($file);
        if ( -d $file ) {
            $image = 'httpd-unix-directory.png';
            if ( $file ne '..' ) {
                my ( $mode, $size ) = ( stat(_) )[ 2, 7 ];
                $size = int( $size / 1024 );
                $mode = sprintf( '%o', $mode );
                $mode = substr( $mode, 2, 4 );

                #octal
                if ( $dirselect ne '-1' ) {
                    if ($usesameframe) {
                        print qq{<tr><td><a href="$html_safe_script_uri?dir=${uri_safe_dir}/${uri_safe_file}"><img src="../mimeicons/$image" border="0"></a></td><td><a href="${dirselect}?dir=$uri_safe_dir&file=$uri_safe_file">$html_safe_file</a></td><td></td><td>$mode</td></tr>\n};

                    }
                    else {
                        print qq{<tr><td><a href="$html_safe_script_uri?dir=${uri_safe_dir}/${uri_safe_file}"><img src="../mimeicons/$image" border="0"></a></td><td><a href="${dirselect}?dir=$uri_safe_dir&file=$uri_safe_file" target=infofr>$html_safe_file</a></td><td></td><td>$mode</td></tr>\n};
                    }
                }
                else {
                    print qq{<tr><td><a href="$html_safe_script_uri?dir=${uri_safe_dir}/${uri_safe_file}"><img src="../mimeicons/$image" border="0"></a></td><td>$html_safe_file</td><td></td><td>$mode</td></tr>\n};
                }
            }
            else {
                if ( $dir ne $Cpanel::homedir && $dir ne $Cpanel::abshomedir ) {
                    my @DIRS   = split( /\//, $dir );
                    my $n      = 0;
                    my $topdir = '';
                    foreach my $dirs (@DIRS) {
                        $topdir = $topdir . $dirs . '/' if $#DIRS != $n;
                        $n++;
                    }
                    my $uri_safe_topdir = Cpanel::Encoder::URI::uri_encode_str($topdir);
                    print qq{<tr><td><a href="$html_safe_script_uri?dir=$uri_safe_topdir"><img src="../mimeicons/$image" border="0"></a></td><td><a href="$html_safe_script_uri?dir=$uri_safe_topdir"><b>Up one level</b></a></td><td></td><td></td></tr>\n};
                }
            }
        }
    }

    $image = 'text-x-generic.png';
    if ( !$chooser ) {
        print qq{<tr><td><a target="infofr" href="createfile.html?dir=$uri_safe_dir"><img src="../mimeicons/$image" border="0"></a></td><td><a target=infofr href="createfile.html?dir=$uri_safe_dir"><b>Create New File</b></a></td><td></td><td></td></tr>\n};
    }
    my $rMIMEINFO = _loadmimeinfo();
    foreach my $file ( sort @DIRLS ) {
        my $uri_safe_file  = Cpanel::Encoder::URI::uri_encode_str($file);
        my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);
        if ( !-d $file ) {
            my ( $mode, $size ) = ( stat(_) )[ 2, 7 ];
            my $filetype = $Cpanel::Fcntl::Types::FILE_TYPES{ $mode & 0170000 };    #& 0170000 = Fcntl::S_IFMT
            my ( $mimeinfo, $mimename ) = _getmimename( $dir, $file, 'file', $rMIMEINFO, 1 );
            $size = int( $size / 1024 );
            $mode = sprintf( '%o', $mode );
            $mode = substr( $mode, 2, 4 );

            #octal
            if ( $select ne '-1' ) {
                if ($usesameframe) {
                    print qq{<tr><td width="50" align="left"><a href="${select}?dir=$uri_safe_dir&file=$uri_safe_file"><img border="0" src=\"../mimeicons/$mimename.png\"></a></td><td align="left"><a href="${select}?dir=$uri_safe_dir&file=$uri_safe_file">$html_safe_file</a></td><td>$size k</td><td>$mode</td></tr>\n};
                }
                else {
                    print qq{<tr><td width="50" align="left"><a href="${select}?dir=$uri_safe_dir&file=$uri_safe_file" target="infofr"><img border="0" src="../mimeicons/$mimename.png"></a></td><td align="left"><a href="${select}?dir=$uri_safe_dir&file=$uri_safe_file" target="infofr">$html_safe_file</a></td><td>$size k</td><td>$mode</td></tr>\n};
                }
            }
            else {
                print qq{<tr><td><img src="../mimeicons/$mimename.png" border="0"></td><td>$html_safe_file</td><td></td><td>$mode</td></tr>\n};
            }
        }
    }
    print '</table>';
    return;
}

sub dofileop {
    return if _notallowed();

    my ( $opdir, $opfile, $dir, $fileop ) = @_;

    $dir    = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $opdir  = Cpanel::SafeDir::safedir($opdir);
    $opfile = safefile($opfile);
    my $html_safe_dir    = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_opdir  = Cpanel::Encoder::Tiny::safe_html_encode_str($opdir);
    my $html_safe_opfile = Cpanel::Encoder::Tiny::safe_html_encode_str($opfile);

    my $locale = Cpanel::Locale->get_handle();

    if ( !-d $dir ) {
        print $locale->maketext( 'Internal error: can’t find that folder: [_1]', $html_safe_dir ), "\n";
        return;
    }

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    $dir =~ s/\/$//g;

    if ( !-d $opdir ) {
        print $locale->maketext( 'Internal error: can’t find that folder: [_1]', $html_safe_dir ), "\n";
        return;
    }
    $opdir =~ s/\/$//g;

    if ( $fileop eq 'move' ) {
        if ( -e "$dir/$opfile" ) {
            print $locale->maketext( 'Could not move “[_1]” to “[_2]” because it already exists.', $html_safe_opfile, "$html_safe_dir/$html_safe_opfile" ) . "\n";
            return;
        }
        rename "$opdir/$opfile", "$dir/$opfile"
          or print $locale->maketext( 'Cannot move “[_1]”: [_2]', $html_safe_opfile, $! ) . "\n";
    }
    if ( $fileop eq 'copy' ) {
        Cpanel::FileUtils::Copy::safecopy( "$opdir/$opfile", $dir );
    }
    return;
}

sub changeperm {
    return if _notallowed();

    my ( $dir, $file, $ur, $uw, $ux, $gr, $gw, $gx, $wr, $ww, $wx, $doubledecode ) = @_;
    my $locale = Cpanel::Locale->get_handle();

    if ($doubledecode) {

        #doubledecode is DOUBLE URI ENCODING not html ENCODING
        $dir  = Cpanel::Encoder::URI::uri_decode_str($dir);
        $file = Cpanel::Encoder::URI::uri_decode_str($file);
    }

    if ( !$dir && !$file ) {
        print $locale->maketext( 'Internal error: can’t find that folder: [_1]', '(null)' ), "\n";
        return;
    }

    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);

    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    if ( !-d $dir ) {
        print $locale->maketext( 'Internal error: can’t find that folder: [_1]', $html_safe_dir ), "\n";
        return;
    }

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    $dir =~ s/\/$//g;

    my $u    = ( $ur + $ux + $uw );
    my $g    = ( $gr + $gx + $gw );
    my $w    = ( $wr + $wx + $ww );
    my $perm = "0${u}${g}${w}";

    chmod( oct($perm), "$dir/$file" ) or do {
        print STDERR "$html_safe_dir/$html_safe_file chmod failed: $!";
        print "$html_safe_dir/$html_safe_file chmod failed: $!";
        return;
    };
    my $perms_string = "0${u}${g}${w}";
    print $locale->maketext( 'Successfully set permissions on “[_1]” to “[_2]”.', $html_safe_file, $perms_string ) . "\n";
    return;
}

sub showperm {
    return if _notallowed(1);
    my ( $dir, $file ) = @_;

    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);

    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    my $locale = Cpanel::Locale->get_handle();

    if ( !-d $dir || !-r $dir ) {
        print $locale->maketext( 'Internal error: can’t find that folder: [_1]', $html_safe_dir ), "\n";
        return;
    }
    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    $dir =~ s/\/$//g;

    my $perm = ( stat($file) )[2] & 0777;

    my $ur = $perm & 0400 ? 'checked="checked"' : '';
    my $uw = $perm & 0200 ? 'checked="checked"' : '';
    my $ux = $perm & 0100 ? 'checked="checked"' : '';

    my $gr = $perm & 0040 ? 'checked="checked"' : '';
    my $gw = $perm & 0020 ? 'checked="checked"' : '';
    my $gx = $perm & 0010 ? 'checked="checked"' : '';

    my $wr = $perm & 0004 ? 'checked="checked"' : '';
    my $ww = $perm & 0002 ? 'checked="checked"' : '';
    my $wx = $perm & 0001 ? 'checked="checked"' : '';

    print <<"EOM";
<tr>
   <td><b>Mode</b></td>
   <td>User</td><td>Group</td>
   <td>World</td>
</tr>
<tr>
   <td>Read</td>
   <td><input $ur type="checkbox" name="ur" value="4" onClick="calcperm();"></td>
   <td><input $gr type="checkbox" name="gr" value="4" onClick="calcperm();"></td>
   <td><input $wr type="checkbox" name="wr" value="4" onClick="calcperm();"></td>
</tr>
<tr>
    <td>Write</td>
    <td><input $uw type="checkbox" name="uw" value="2" onClick="calcperm();"></td>
    <td><input $gw type="checkbox" name="gw" value="2" onClick="calcperm();"></td>
    <td><input $ww type="checkbox" name="ww" value="2" onClick="calcperm();"></td>
</tr>
<tr>
    <td>Execute</td>
    <td><input $ux type="checkbox" name="ux" value="1" onClick="calcperm();"></td>
    <td><input $gx type="checkbox" name="gx" value="1" onClick="calcperm();"></td>
    <td><input $wx type="checkbox" name="wx" value="1" onClick="calcperm();"></td>
</tr>
<tr>
    <td>Permission</td>
    <td><input type="text" name="u" size="1" readonly="readonly"></td>
    <td><input type="text" name="g" size="1" readonly="readonly"></td>
    <td><input type="text" name="w" size="1" readonly="readonly"></td>
</tr>
EOM
    return;
}

sub fileops {
    return if _notallowed(1);    # nothing in orig

    my ( $opdir, $opfile, $dir, $fileop ) = @_;

    $dir    = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $opfile = safefile($opfile);
    $opdir  = Cpanel::SafeDir::safedir($opdir);

    my $html_safe_dir    = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_opdir  = Cpanel::Encoder::Tiny::safe_html_encode_str($opdir);
    my $html_safe_opfile = Cpanel::Encoder::Tiny::safe_html_encode_str($opfile);

    my $uri_safe_dir    = Cpanel::Encoder::URI::uri_encode_str($dir);
    my $uri_safe_opdir  = Cpanel::Encoder::URI::uri_encode_str($opdir);
    my $uri_safe_opfile = Cpanel::Encoder::URI::uri_encode_str($opfile);
    my $uri_safe_fileop = Cpanel::Encoder::URI::uri_encode_str($fileop);

    my $locale = Cpanel::Locale->get_handle();

    if ( !-d $dir || !-r $dir ) {
        print $locale->maketext( 'Internal error: can’t find that folder: [_1]', $html_safe_dir ), "\n";
        return;
    }
    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    $dir =~ s/\/$//g;
    my $vdir = $dir;
    $vdir =~ s/^$Cpanel::abshomedir//g;
    $vdir =~ s/^\///g;

    opendir my $pwd_dh, '.' or $logger->die("Could not open PWD: $!");
    my @DIRLS = grep( !/^\.$/, readdir $pwd_dh );    # onyl '.' will be excluded
    closedir $pwd_dh;

    my $uri_safe_file = '';
    my $image         = 'httpd-unix-directory.png';

    print
      qq{<a href="$ENV{'SCRIPT_URI'}?opfile=$uri_safe_opfile&opdir=$uri_safe_opdir&fileop=$uri_safe_fileop&dir=$uri_safe_dir/$uri_safe_file"><img src="../mimeicons/$image" border=0></a> <a href="dofileop.html?dir=$uri_safe_dir/$uri_safe_file&opfile=$uri_safe_opfile&opdir=$uri_safe_opdir&fileop=$uri_safe_fileop" target="infofr"><a href="$ENV{'SCRIPT_URI'}?opfile=$uri_safe_opfile&opdir=$uri_safe_opdir&fileop=$uri_safe_fileop&dir=/">/</a> };

    my $tdir;
    foreach my $dirs ( split /\//, $vdir ) {
        $tdir = $tdir . "$dirs/";
        my $uri_safe_tdir  = Cpanel::Encoder::URI::uri_encode_str($tdir);
        my $html_safe_dirs = Cpanel::Encoder::Tiny::safe_html_encode_str($dirs);
        print qq{ <a href="$ENV{'SCRIPT_URI'}?opfile=$uri_safe_opfile&opdir=$uri_safe_opdir&fileop=$uri_safe_fileop&dir=/$uri_safe_tdir">$html_safe_dirs</a> / };
    }
    print "(Current Folder)</a>\n<br>";

    foreach my $file ( sort @DIRLS ) {
        my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);
        my $uri_safe_file  = Cpanel::Encoder::URI::uri_encode_str($file);
        if ( -d $file ) {
            $image = 'httpd-unix-directory.png';
            if ( $file ne '..' ) {
                print qq{<a href="$ENV{'SCRIPT_URI'}?opfile=$uri_safe_opfile&opdir=$uri_safe_opdir&fileop=$uri_safe_fileop&dir=$uri_safe_dir/$uri_safe_file"><img src="../mimeicons/$image" border=0></a> <a href="dofileop.html?dir=$uri_safe_dir/$uri_safe_file&opfile=$uri_safe_opfile&opdir=$uri_safe_opdir&fileop=$uri_safe_fileop" target="infofr">$html_safe_file</a><br />\n};
            }
            else {
                my $topdir;
                if (   $dir ne ${Cpanel::homedir}
                    && $dir ne ${Cpanel::abshomedir} ) {
                    my @DIRS = split( /\//, $dir );
                    my $n    = 0;
                    foreach my $dirs (@DIRS) {
                        $topdir = $topdir . $dirs . '/' if $#DIRS != $n;
                    }
                    $n++;
                }
                my $uri_safe_topdir = Cpanel::Encoder::URI::uri_encode_str($topdir);
                print qq{<a href="$ENV{'SCRIPT_URI'}?opfile=$uri_safe_opfile&opdir=$uri_safe_opdir&fileop=$uri_safe_fileop&dir=$uri_safe_topdir"><img src="../mimeicons/$image" border="0"></a> <a href="$ENV{'SCRIPT_URI'}?dir=$uri_safe_topdir&opfile=$uri_safe_opfile&opdir=$uri_safe_opdir&fileop=$uri_safe_fileop"><b>Up one level</b></a><br />\n};
            }
        }
    }
}

sub killdirs {
    return if _notallowed();

    my $removed = 0;
    foreach my $dir ( keys %Cpanel::FORM ) {
        next if ( $dir !~ /^dir:/ );
        $dir =~ s/^dir://g;
        $dir = Cpanel::SafeDir::safedir($dir);
        my @cmd = ( 'rm', '-rfv', '--', $dir );
        print Cpanel::SafeRun::Errors::saferunallerrors(@cmd);
        $removed = 1;
    }
    if ($removed) {
        if ( -e "$Cpanel::homedir/.cpanel/ducache" ) {
            unlink("$Cpanel::homedir/.cpanel/ducache");
        }
    }
}

sub showtrash {
    return if _notallowed(1);

    my $image         = 'httpd-unix-directory.png';
    my $dir           = $Cpanel::abshomedir . '/.trash';
    my $html_safe_dir = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $uri_safe_dir  = Cpanel::Encoder::URI::uri_encode_str($dir);

    if ( !-d $dir ) {
        mkdir $dir, 0700 or do {
            print "<br />Unable to create trash folder. You do not seem " . "to have the necessary permissions! (System Error: $!)\n";
            return;
        };
    }

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    opendir my $pwd_dh, '.'
      or $logger->die("Could not open PWD ($html_safe_dir): $!");
    my @DIRLS =
      grep( !/^\.\.?$/, readdir $pwd_dh );    # onyl '.' and '..' will be excluded
    closedir $pwd_dh;

    foreach my $file ( sort @DIRLS ) {
        if ( -d $file ) {
            my $uri_safe_file  = Cpanel::Encoder::URI::uri_encode_str($file);
            my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);
            print qq{<a href="restore.html?file=$uri_safe_file"><img src="../mimeicons/$image" border="0"></a> <a href="restore.html?file=$uri_safe_file" target="infofr">$html_safe_file</a><br />\n};
        }
    }

    my $rMIMEINFO = _loadmimeinfo();

    foreach my $file (@DIRLS) {
        if ( !-d $file && $file ne '.trash_restore' ) {
            my $uri_safe_file  = Cpanel::Encoder::URI::uri_encode_str($file);
            my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

            my ( $mode, $size ) = ( stat(_) )[ 2, 7 ];
            my $filetype = $Cpanel::Fcntl::Types::FILE_TYPES{ $mode & 0170000 };    #& 0170000 = Fcntl::S_IFMT
            my ( $mimeinfo, $mimename ) = _getmimename( $dir, $file, 'file', $rMIMEINFO, 1 );
            $image = $mimename . '.png';

            print qq{<a href="restore.html?file=$uri_safe_file" target=infofr><img border="0" src="../mimeicons/$image"></a> <a href="select.html?dir=$uri_safe_dir&file=$uri_safe_file" target="infofr">$html_safe_file</a><br />\n};
        }
    }
    return;
}

sub _slurp_via_iconv_r {

    # Readin the file into the return value
    return __loadfile_via_iconv( 1, @_ );
}

sub _print_html_via_iconv {

    # Print the file to STDOUT
    return __loadfile_via_iconv( 0, @_ );
}

sub __loadfile_via_iconv {

    # Load a file via the ICONV program to convert the character set
    # from the from_charset to the to_charset.
    # Arguments:
    #   $spool         - bool - true means return the content, false mean print the content.
    #   $path          - string - complete path to the file to process.
    #   $from_charset  - string - valid character set to convert the file from.
    #   $to_charset    - string - valid character set to convert the file to.

    # Get the arguments.
    my ( $spool, $path, $from_charset, $to_charset ) = @_;

    my $buffer;

    # Sanitize the input
    $from_charset ||= Cpanel::Encoding::guess_file($path);
    $to_charset   ||= Cpanel::Locale->get_handle()->encoding();    #utf-8 probably

    # Normalize:
    # ICONV doesn't automatically recognize "usascii" and "us-ascii" as the same,
    # so we leave punctuation in.
    tr{A-Z}{a-z} for ( $from_charset, $to_charset );

    # Determine if we need ICONV?
    my $use_iconv = $from_charset ne $to_charset;

    # Change the data to be suitable for the browser, namely: make it utf-8
    if ($use_iconv) {

        # We need to convert the file to another charset then spit it out

        # Find the ICONV binary file
        my $iconv_binary = Cpanel::Binaries::path('iconv');
        if ( -x $iconv_binary ) {

            my @cmd = ( $iconv_binary, '-f', $from_charset, '-t', $to_charset, $path );

            my $pid = open my $fh, '-|';

            if ( !defined $pid ) {
                Cpanel::Logger->new()->warn("Could not fork as $Cpanel::user: $!");
                return;
            }

            # TODO: This should probably check for iconv errors in the
            # unlikely-but-possible case of iconv erroring out.
            if ($pid) {
                my $cur;
                if ($spool) {

                    # Spool the content
                    while ( read $fh, $cur, $READ_BUFFER_SIZE ) {
                        $buffer .= $cur;
                    }
                }
                else {
                    # Flush the content as it read
                    while ( read $fh, $cur, $READ_BUFFER_SIZE ) {
                        print Cpanel::Encoder::Tiny::safe_html_encode_str($cur);
                    }
                }

                close $fh;
                waitpid $pid, 0;
            }
            else {
                exec(@cmd) or do {
                    Cpanel::Logger->new()->warn("Could not exec @cmd as $Cpanel::user: $!");
                    return;
                };
            }
        }
        else {
            Cpanel::Logger->new()->warn("Could not locate iconv binary as $Cpanel::user");
        }
    }
    elsif ( open my $read_fh, '<', $path ) {

        # We just need to open the file and process it
        my $cur;
        if ($spool) {
            while ( read $read_fh, $cur, $READ_BUFFER_SIZE ) {
                $buffer .= $cur;
            }
        }
        else {
            while ( read $read_fh, $cur, $READ_BUFFER_SIZE ) {
                print Cpanel::Encoder::Tiny::safe_html_encode_str($cur);
            }
        }

        close $read_fh;
    }
    else {
        Cpanel::Logger->new()->warn("Could not open $path as $Cpanel::user: $!");
    }

    return length($buffer) ? \$buffer : ();
}

sub fmpushfile {
    my ( $dir, $file, $from_charset ) = @_;

    return if _notallowed(1);

    $dir = defined $dir && $dir ? safedir($dir) : $Cpanel::abshomedir;
    my $path = $dir . '/' . safefile($file);

    if ( -r $path ) {
        if ( defined $from_charset ) {

            # Legacy themes used to pass '1' and custom themes still might. If this happens try to use the value passed in the request.
            if ( $from_charset eq '1' ) {
                $from_charset = $Cpanel::FORM{'file_charset'};
            }

            if ( $from_charset eq '_DETECT_' ) {
                undef $from_charset;
            }
        }
        _print_html_via_iconv( $path, $from_charset );
    }
    return;
}

## DEPRECATED!
sub api2_savefile {
    my %OPTS = ( @_, 'api.quiet' => 1 );

    # Fix parameter name changes
    $OPTS{'file'} = delete $OPTS{'filename'};
    if ( $OPTS{'charset'} ) {
        $OPTS{'to_charset'} = delete $OPTS{'charset'};
    }
    else {
        $OPTS{'to_charset'} = 'UTF-8';
    }
    $OPTS{'from_charset'} = 'UTF-8';
    $OPTS{'fallback'}     = delete $OPTS{'utf8_fallback'} if exists $OPTS{'utf8_fallback'};

    my $result = Cpanel::API::wrap_deprecated( 'Fileman', 'save_file_content', \%OPTS );
    my $data   = $result->data();

    # Fix the results
    if ($data) {
        $data->{'charset'} = delete $data->{'to_charset'};
        delete $data->{'from_charset'};
    }

    if ( $result->errors() ) {
        return;
    }
    else {
        return $data;
    }
}

sub fmsavefile {

    # Security:
    return if _notallowed( 0, 1 );    #needed to save css etc.

    # local $Cpanel::IxHash::Modify = 'none'; needs done so that $page is raw... -> handled by expvar call in cpanel.pl 2149
    my ( $dir, $file, $page, $stripnewline, $doubledecode, $to_charset ) = @_;

    #assume we are coming from UTF-8 if "to_charset" is given

    if (
        $doubledecode
        || (   $Cpanel::FORM{'doubledecode'}
            && $Cpanel::FORM{'doubledecode'} eq '1' )
    ) {

        #doubledecode is DOUBLE URI ENCODING not html ENCODING
        $dir  = Cpanel::Encoder::URI::uri_decode_str($dir);
        $file = Cpanel::Encoder::URI::uri_decode_str($file);
    }

    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);

    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    #Bareword filehandles are necessary here so that open3() will
    #use the filehandles as-is rather than making dupes.
    #(Is there a way to do this with lexical filehandles..?)
    open FILEOUT, '>', $file
      or $logger->die("open $html_safe_file failed: $!");
    $page =~ s/\r//g;
    if ($stripnewline) { $page =~ s/\n$//g; }

    my $use_iconv = $to_charset && $to_charset !~ m{\Autf-?8\z}i;

    my $iconv_error;
    if ($use_iconv) {
        my $iconv_binary = Cpanel::Binaries::path('iconv');
        if ( -x $iconv_binary ) {
            my @cmd = ( $iconv_binary, '-f' => 'UTF-8', '-t' => $to_charset );

            #No SafeRun since those functions all slurp
            my $pid = IPC::Open3::open3( \*ICONV_IN, '>&FILEOUT', \*ICONV_ERR, @cmd );

            if ($pid) {
                print ICONV_IN $page;
                close ICONV_IN;

                local $/;
                my $iconv_error_str = <ICONV_ERR>;
                close ICONV_ERR;

                waitpid $pid, 0;

                if ($iconv_error_str) {
                    $iconv_error     = 1;
                    $iconv_error_str = Cpanel::Encoder::Tiny::safe_html_encode_str($iconv_error_str);
                    print "<br />iconv error converting from UTF-8 to " . Cpanel::Encoder::Tiny::safe_html_encode_str($to_charset) . ": $iconv_error_str";

                    #throw away whatever iconv may have printed
                    close FILEOUT;
                    open FILEOUT, '>', $file;
                }
            }
            else {
                $iconv_error = 1;
                my $logger = Cpanel::Logger->new();
                $logger->warn("Failed to execute $iconv_binary: $!");
                close ICONV_IN;
                close FILEOUT;
                my $html_err = Cpanel::Encoder::Tiny::safe_html_encode_str($!);
                print "<br />Unable to execute iconv binary to use for converting character encodings: $html_err";
            }
        }
        else {
            $iconv_error = 1;
            print "<br />Unable to locate iconv binary to use for converting character encodings!";
        }

        if ($iconv_error) {

            #all iconv error cases have a particular error message above
            #as well as this notice:
            print "<br />Saving $html_safe_file in UTF-8...";
        }
    }

    if ( !$use_iconv || $iconv_error ) {
        print FILEOUT $page;
    }

    ;    # placeholder until $page can be passed as raw HTML, see above...
    if (   ( $dir =~ /(public_html|www)[\/]*$/ )
        && $file =~ /^\d+\.shtml/
        && ( length($page) < 600 ) ) {
        print FILEOUT "\n<!-- \n";
        print FILEOUT q{ } x int( 600 - length($page) );
        print FILEOUT "\n--> \n";
    }
    close FILEOUT;
    return;
}

sub savehtmlfile {
    return if _notallowed();

    # local $Cpanel::IxHash::Modify = 'none'; needs done so that $page is raw... -> handled by expvar call in cpanel.pl 2149
    my ( $dir, $file, $page, $skipfile, $doubledecode ) = @_;

    if (
        $doubledecode
        || (   $Cpanel::FORM{'doubledecode'}
            && $Cpanel::FORM{'doubledecode'} eq '1' )
    ) {

        #doubledecode is DOUBLE URI ENCODING not html ENCODING
        $dir  = Cpanel::Encoder::URI::uri_decode_str($dir);
        $file = Cpanel::Encoder::URI::uri_decode_str($file);
    }

    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);
    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    if ( !$skipfile ) {    # abort
        chdir($dir) || do {
            print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
            return;
        };
        open my $write_fh, '>', $file
          or $logger->die("open $html_safe_file failed: $!");
        print {$write_fh} $page;
        close $write_fh;
    }

    return;
}

sub aborthtmlfile {
    return if _notallowed();
    my ( $dir, $file, $doubledecode ) = @_;

    if ( $doubledecode || ( $Cpanel::FORM{'doubledecode'} && $Cpanel::FORM{'doubledecode'} eq '1' ) ) {

        #doubledecode is DOUBLE URI ENCODING not html ENCODING
        $dir  = Cpanel::Encoder::URI::uri_decode_str($dir);
        $file = Cpanel::Encoder::URI::uri_decode_str($file);
    }

    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);

    chdir($dir) || do {
        my $html_safe_dir = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    return;
}

sub fileimg {
    return if _notallowed(1);    # nothing in orig

    my $rMIMEINFO = _loadmimeinfo();
    my ( $dir, $file ) = @_;
    $dir = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    if ( $file eq '' ) {
        my @TDIR = split( /\//, $dir );
        $file = pop(@TDIR);
        $dir  = join( '/', @TDIR );
    }
    $file = safefile($file);

    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    my ( $mimetype, $mimename ) = _getmimename( $dir, $file, -d "$dir/$file" ? 'dir' : 'file', $rMIMEINFO, 1 );
    return qq{<img src="../mimeicons/$mimename.png" align="absmiddle" alt="$mimetype">};
}

sub api2_getfileactions {

    #$API{'getfileactions'}{'modify'} = 'none';
    my %CFG = @_;

    my $dir     = $CFG{'dir'};
    my $file    = $CFG{'file'};
    my $newedit = $CFG{'newedit'};
    $file = safefile($file);
    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;

    my $html_safe_dir = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    my $safedir = $dir;
    $safedir =~ s/^$Cpanel::abshomedir//g;

    my $rMIMEINFO = _loadmimeinfo();
    my ( $mode, $size ) = ( stat($file) )[ 2, 7 ];
    my $filetype = $Cpanel::Fcntl::Types::FILE_TYPES{ $mode & 0170000 };    #& 0170000 = Fcntl::S_IFMT

    my $locale = Cpanel::Locale->get_handle();

    my $filenfo = Cpanel::SafeRun::Errors::saferunnoerror( 'file', '--', $file );
    $filenfo =~ s/^(\S+)://g;
    my @ACTLIST;

    my ( $mimetype, $mimename ) = _getmimename( $dir, $file, 'file', $rMIMEINFO );
    my $uri_encoded_dir  = Cpanel::Encoder::URI::uri_encode_str($dir);
    my $uri_encoded_file = Cpanel::Encoder::URI::uri_encode_str($file);

    if ( $filenfo =~ /text/ ) {
        push(
            @ACTLIST,
            {
                action     => 'show',
                actionurl  => "showfile.html?dir=$uri_encoded_dir&file=$uri_encoded_file",
                target     => "viewer",
                actionname => $locale->maketext('Show File')
            }
        );
    }
    else {
        push(
            @ACTLIST,
            {
                action     => 'showcontents',
                actionurl  => "showfile.html?dir=$uri_encoded_dir&file=$uri_encoded_file",
                target     => "viewer",
                actionname => $locale->maketext('Show File Contents')
            }
        );
    }

    if ( $filenfo =~ /compress/ || $filenfo =~ /archive/ ) {
        push(
            @ACTLIST,
            {
                action     => 'extract',
                actionurl  => "extractfile.html?dir=$uri_encoded_dir&file=$uri_encoded_file",
                target     => "viewer",
                actionname => $locale->maketext('Extract File Contents')
            }
        );
    }

    push(
        @ACTLIST,
        {
            action     => 'delete',
            actionurl  => "trashit.html?dir=$uri_encoded_dir&file=$uri_encoded_file",
            target     => "file",
            actionname => $locale->maketext('Delete File')
        }
    );

    if ( $filenfo !~ /image/
        && ( $filenfo =~ /text/ || $filenfo =~ /data/ || $filenfo =~ /empty/ ) ) {
        if ( $size < 250000 ) {
            push(
                @ACTLIST,
                {
                    action     => 'codeedit',
                    actionurl  => ( ( $newedit ? 'editit_code_landing.html' : 'editit_code.html' ) . "?dir=$uri_encoded_dir&file=$uri_encoded_file" ),
                    target     => ( $newedit ? 'file' : 'editor' ),
                    actionname => $locale->maketext('Edit File with Code Editor')
                }
            );
        }
        push(
            @ACTLIST,
            {
                action     => 'edit',
                actionurl  => ( ( $newedit ? 'editit_landing.html' : 'editit.html' ) . "?dir=$uri_encoded_dir&file=$uri_encoded_file" ),
                target     => ( $newedit ? 'file' : 'editor' ),
                actionname => $locale->maketext('Edit File')
            }
        );
    }

    push(
        @ACTLIST,
        {
            action     => 'chmod',
            actionurl  => "perm.html?dir=$uri_encoded_dir&file=$uri_encoded_file",
            target     => "file",
            actionname => $locale->maketext('Change Permissions')
        }
    );
    push(
        @ACTLIST,
        {
            action     => 'rename',
            actionurl  => "rename.html?dir=$uri_encoded_dir&file=$uri_encoded_file",
            target     => "file",
            actionname => $locale->maketext('Rename File')
        }
    );
    push(
        @ACTLIST,
        {
            action     => 'copy',
            actionurl  => "fileop.html?opdir=$uri_encoded_dir&opfile=$uri_encoded_file&fileop=copy",
            target     => "dir",
            actionname => $locale->maketext('Copy File')
        }
    );
    push(
        @ACTLIST,
        {
            action     => 'move',
            actionurl  => "fileop.html?opdir=$uri_encoded_dir&opfile=$uri_encoded_file&fileop=move",
            target     => "dir",
            actionname => $locale->maketext('Move File')
        }
    );
    push(
        @ACTLIST,
        {
            action     => 'download',
            actionurl  => "$ENV{'cp_security_token'}/download?file=$uri_encoded_dir/$uri_encoded_file",
            target     => "file",
            actionname => $locale->maketext('Download File')
        }
    );

    if ( $safedir =~ /^\/?(www|public_html)/ ) {
        my $htmldir = $safedir;
        $htmldir =~ s/^\/?(www|public_html)\/?//g;
        $file    =~ s/^\///g;
        $htmldir = '/' . $htmldir if $htmldir ne '/' && $htmldir ne '';
        $file    = '/' . $file;
        push(
            @ACTLIST,
            {
                action     => 'url',
                actionurl  => "http://www.$Cpanel::CPDATA{'DNS'}" . Cpanel::Encoder::URI::uri_encode_dirstr("${htmldir}${file}"),
                target     => "_blank",
                actionname => "URL: http://www.$Cpanel::CPDATA{'DNS'}" . Cpanel::Encoder::URI::uri_encode_dirstr("${htmldir}${file}")
            }
        );
    }
    my @RSD;
    push(
        @RSD,
        {
            dir      => $dir,
            file     => $file,
            mimetype => $mimetype,
            mimename => $mimename,
            fileinfo => $filenfo,
            actions  => \@ACTLIST
        }
    );
    return @RSD;
}

sub showactions {    ## no critic qw(Subroutines::RequireArgUnpacking)
    return if _notallowed(1);

    my ( $dir, $file, $page, $usecodeedit ) = @_;
    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);

    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);
    my $uri_safe_dir   = Cpanel::Encoder::URI::uri_encode_str($dir);
    my $uri_safe_file  = Cpanel::Encoder::URI::uri_encode_str($file);

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    my $safedir = $dir;
    $safedir =~ s/^$Cpanel::abshomedir//g;

    my $rMIMEINFO = _loadmimeinfo();

    my ( $mode, $size ) = ( stat($file) )[ 2, 7 ];
    my $filetype = $Cpanel::Fcntl::Types::FILE_TYPES{ $mode & 0170000 };    #& 0170000 = Fcntl::S_IFMT
    my ( $mimeinfo, $mimename ) = _getmimename( $dir, $file, 'file', $rMIMEINFO, 1 );
    my $image = $mimename . '.png';

    my $filenfo = Cpanel::SafeRun::Errors::saferunnoerror( 'file', '--', $file );
    $filenfo =~ s/^(\S+)://g;
    my $html_safe_filenfo = Cpanel::Encoder::Tiny::safe_html_encode_str($filenfo);

    print "<img src=\"../mimeicons/$image\"> <b><font size=+1>$html_safe_file</font></b>\n<br>";
    print "File Type: $html_safe_filenfo\n<br>";
    if ( $filenfo =~ /text/ ) {
        print "<br><a href=\"showfile.html?dir=${uri_safe_dir}&file=$uri_safe_file\" target=\"viewer\">Show File</a>\n";
    }
    else {
        print "<br><a href=\"showfile.html?dir=${uri_safe_dir}&file=$uri_safe_file\" target=\"viewer\">Show File Contents</a>\n";
    }

    if ( $filenfo =~ /compress/ || $filenfo =~ /archive/ ) {
        print "<br><a href=\"extractfile.html?dir=${uri_safe_dir}&file=$uri_safe_file\" target=\"viewer\">Extract File Contents</a>\n";
    }

    print "<br><a href=\"trashit.html?dir=$uri_safe_dir&file=$uri_safe_file\">Delete File</a>\n";
    if ( $filenfo !~ /image/
        && ( $filenfo =~ /text/ || $filenfo =~ /data/ || $filenfo =~ /empty/ ) ) {
        if ( $usecodeedit && $size < 250000 ) {
            print "<br><a href=\"editit_code.html?dir=$uri_safe_dir&file=$uri_safe_file\" target=\"editor\">Edit File with Code Editor</a>\n";
        }
        print "<br><a href=\"editit.html?dir=$uri_safe_dir&file=$uri_safe_file\" target=\"editor\">Edit File</a>\n";
    }

    print "<br><a href=\"perm.html?dir=${uri_safe_dir}&file=$uri_safe_file\">Change Permissions</a>\n";
    print "<br><a href=\"rename.html?dir=${uri_safe_dir}&file=$uri_safe_file\">Rename File</a>\n";
    print "<br><a href=\"fileop.html?opdir=${uri_safe_dir}&opfile=$uri_safe_file&fileop=copy\" target=\"filemain\">Copy File</a>\n";
    print "<br><a href=\"fileop.html?opdir=${uri_safe_dir}&opfile=$uri_safe_file&fileop=move\" target=\"filemain\">Move File</a>\n";

    if ( $safedir =~ /^\/?(www|public_html)/ ) {
        if ( -w $file && $filenfo =~ /html/i || $file =~ /\.s?html?$/ ) {
            print "<br><a href=\"htmledit.html?dir=${uri_safe_dir}&file=$uri_safe_file\" target=_blank><b>Html Editor</b></a>\n";
        }
        my $htmldir = $safedir;
        $htmldir =~ s/^\/?(www|public_html)\/?//g;
        $file    =~ s/^\///g;
        $htmldir = '/' . $htmldir if $htmldir ne '/' && $htmldir ne '';
        $file    = '/' . $file;
        print "<br><br>File Url: <a href=\"http://www.$Cpanel::CPDATA{'DNS'}" . Cpanel::Encoder::URI::uri_encode_dirstr("${htmldir}${file}") . "\" target=_blank><b>http://www.$Cpanel::CPDATA{'DNS'}" . Cpanel::Encoder::URI::uri_encode_dirstr("${htmldir}${file}") . "</b></a>\n";
    }

    return;
}

sub showdiractions {
    my ( $dir, $file ) = @_;

    return if _notallowed(1);

    $dir = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    my $html_safe_dir = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    if ( !$dir ) {
        print "Invalid directory: $html_safe_dir!";
        return;
    }
    $file = safefile($file);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);
    if ( !$file ) {
        print "Invalid file: $html_safe_file!";
        return;
    }

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    my $uri_safe_file = Cpanel::Encoder::URI::uri_encode_str($file);
    my $uri_safe_dir  = Cpanel::Encoder::URI::uri_encode_str($dir);

    my $image = 'httpd-unix-directory.png';
    print <<"EOM";
<img src="../mimeicons/$image">
<b><font size="+1">$html_safe_file</font></b><br />
<br /><a href="trashit.html?dir=$uri_safe_dir&file=$uri_safe_file">Delete this folder and all files under it</a>
<br /><a href="rename.html?dir=$uri_safe_dir&file=$uri_safe_file">Rename this folder</a>
<br /><a href="perm.html?dir=$uri_safe_dir&file=$uri_safe_file">Change Permissions</a>
<br /><a href="fileop.html?opdir=$uri_safe_dir&opfile=$uri_safe_file&fileop=move" target="filemain">Move this folder</a>
<br /><a href="fileop.html?opdir=$uri_safe_dir&opfile=$uri_safe_file&fileop=copy" target="filemain">Copy this folder</a>
EOM

    return '';
}

sub api2_getdiractions {

    #    $API{'getdiractions'}{'modify'} = 'none';
    #
    my %CFG = @_;

    my $dir  = $CFG{'dir'};
    my $file = $CFG{'file'};
    $dir = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;

    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    if ( !$dir ) {
        $Cpanel::CPERROR{'fileman'} = "Invalid directory: $html_safe_dir!";
        return;
    }
    $file = safefile($file);
    if ( !$file ) {
        $Cpanel::CPERROR{'fileman'} = "Invalid file: $html_safe_file!";
        return;
    }

    chdir($dir) || do {
        $Cpanel::CPERROR{'fileman'} = "Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)";
        return;
    };

    my $uri_encoded_dir  = Cpanel::Encoder::URI::uri_encode_str($dir);
    my $uri_encoded_file = Cpanel::Encoder::URI::uri_encode_str($file);

    my $rMIMEINFO = _loadmimeinfo();
    my ( $mimetype, $mimename ) = _getmimename( $dir, $file, 'dir', $rMIMEINFO );
    my $locale = Cpanel::Locale->get_handle();
    my @ACTLIST;
    push(
        @ACTLIST,
        {
            action     => 'delete',
            target     => 'file',
            actionurl  => "trashit.html?dir=$uri_encoded_dir&file=$uri_encoded_file",
            actionname => $locale->maketext('Delete this folder and all files under it.')
        }
    );
    push(
        @ACTLIST,
        {
            action     => 'chmod',
            target     => 'file',
            actionurl  => "perm.html?dir=$uri_encoded_dir&file=$uri_encoded_file",
            actionname => $locale->maketext('Change Permissions')
        }
    );
    push(
        @ACTLIST,
        {
            action     => 'rename',
            target     => 'file',
            actionurl  => "rename.html?dir=$uri_encoded_dir&file=$uri_encoded_file",
            actionname => $locale->maketext('Rename Folder')
        }
    );

    push(
        @ACTLIST,
        {
            action     => 'copy',
            target     => 'dir',
            actionurl  => "fileop.html?fileop=copy&opdir=$uri_encoded_dir&opfile=$uri_encoded_file",
            actionname => $locale->maketext('Copy This Folder')
        }
    );
    push(
        @ACTLIST,
        {
            action     => 'move',
            target     => 'dir',
            actionurl  => "fileop.html?fileop=move&opdir=$uri_encoded_dir&opfile=$uri_encoded_file",
            actionname => $locale->maketext('Move This Folder')
        }
    );

    my @RSD;
    push(
        @RSD,
        {
            dir      => $dir,
            file     => $file,
            mimename => $mimename,
            mimetype => $mimetype,
            actions  => \@ACTLIST
        }
    );
    return @RSD;
}

sub fmmkdir {
    return if _notallowed();

    my ( $dir, $file ) = @_;

    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);

    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    my $locale           = Cpanel::Locale->get_handle();
    my $newdir           = $dir . '/' . $file;                                     # how did this ever work when the variabel is bever used ??
    my $html_safe_newdir = Cpanel::Encoder::Tiny::safe_html_encode_str($newdir);

    if ( mkdir $newdir, 0755 ) {
        print $locale->maketext( 'Created “[_1]”.', $html_safe_newdir ) . "\n";
    }
    else {
        print $locale->maketext( 'Creation of “[_1]” failed: [_2]', $html_safe_newdir, $! ) . "\n";
    }
    return;
}

sub fmrename {
    return if _notallowed();

    my ( $dir, $file, $filenew, $doubledecode ) = @_;

    if ( !defined $file || !length $file || !defined $filenew || !length $filenew ) {
        print "<br>Both \"file\" and \"filenew\" are required parameters\n";
        return;
    }

    if ($doubledecode) {

        #doubledecode is DOUBLE URI ENCODING not html ENCODING
        $dir  = Cpanel::Encoder::URI::uri_decode_str($dir);
        $file = Cpanel::Encoder::URI::uri_decode_str($file);
    }

    $dir     = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file    = safefile($file);
    $filenew = safefile($filenew);
    my $html_safe_dir     = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file    = Cpanel::Encoder::Tiny::safe_html_encode_str($file);
    my $html_safe_filenew = Cpanel::Encoder::Tiny::safe_html_encode_str($filenew);

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    my $locale = Cpanel::Locale->get_handle();

    if ( rename $file, $filenew ) {
        print $locale->maketext( 'Renamed “[_1]” to “[_2]”.', $html_safe_file, $html_safe_filenew ) . "\n";
    }
    else {
        print $locale->maketext( 'Rename of “[_1]” failed: [_2]', $html_safe_file, $! ) . "\n";
    }
    return;
}

#Returns the filehandle if making a file, or the output of mkdir
sub _prep_dir_file_perms {
    my ($opts_hr) = @_;

    my $dir  = $opts_hr->{'path'} ? Cpanel::SafeDir::safedir( $opts_hr->{'path'} ) : $Cpanel::abshomedir;
    my $file = $opts_hr->{'name'};

    $opts_hr->{'path'} = $dir;
    $opts_hr->{'name'} = $file;

    if ( !length($file) ) {
        $Cpanel::CPERROR{'fileman'} = "No name specified.";
        return;
    }
    elsif ( $file =~ m{$DIRECTORY_SEPARATOR} ) {
        $Cpanel::CPERROR{'fileman'} = "The following character may not be part of a file or directory name: $DIRECTORY_SEPARATOR";
        return;
    }

    my $perms;
    if ( defined $opts_hr->{'permissions'} ) {
        if ( $opts_hr->{'permissions'} !~ m{\A0*[0-7]{1,3}\z} ) {
            $Cpanel::CPERROR{'fileman'} = "Invalid permissions string: $opts_hr->{'permissions'}";
            return;
        }

        $perms = oct $opts_hr->{'permissions'};
    }

    return ( $dir, $file, $perms );
}

sub api2_mkdir {

    my %OPTS = @_;

    my ( $dir, $file, $perms ) = _prep_dir_file_perms( \%OPTS );
    return if !$dir;

    my $old_umask;
    if ( defined $perms ) {
        $old_umask = umask 0;
    }
    else {
        $perms = $DIR_BASE_PERMS - umask;
    }

    my $success = mkdir( "$dir/$file", $perms );

    umask $old_umask if $old_umask;    #no need to re-set a 0 umask

    if ( !$success ) {
        $Cpanel::CPERROR{'fileman'} = "Could not create directory \"$file\" in $dir: " . ( -d $dir ? $! : "Directory $dir does not exist." );
        return;
    }

    return { path => $dir, name => $file, permissions => sprintf( '%04o', $perms ) };
}

my $mkfile_mode = Fcntl::O_CREAT() | Fcntl::O_WRONLY() | Fcntl::O_EXCL();

sub api2_mkfile {

    my %OPTS = @_;

    my $template = $OPTS{'template'};
    my $th;
    if ( defined $template ) {
        if ( $template =~ m{$DIRECTORY_SEPARATOR} ) {
            $Cpanel::CPERROR{'fileman'} = "Invalid file template name: $template";
            return;
        }
        my $open = open( $th, '<', "$FILE_TEMPLATES_DIRECTORY/$template" );
        if ( !$open ) {
            $Cpanel::CPERROR{'fileman'} = "Unable to open template file $template: $!";
            return;
        }
    }

    my ( $dir, $file, $perms ) = _prep_dir_file_perms( \%OPTS );
    return if !$dir;

    my $old_umask;
    if ( defined $perms ) {
        $old_umask = umask 0;
    }
    else {
        $perms = $FILE_BASE_PERMS - umask;
    }

    my $success = sysopen( my $fh, "$dir/$file", $mkfile_mode, $perms );

    umask $old_umask if $old_umask;    #no need to re-set a 0 umask

    if ( !$success ) {
        $Cpanel::CPERROR{'fileman'} = "Could not create file \"$file\" in $dir: " . ( -d $dir ? $! : "Directory $dir does not exist." );
        return;
    }

    if ($th) {
        local $/;
        print {$fh} readline $th;
        close $th;
    }
    close $fh;

    return { path => $dir, name => $file, permissions => sprintf( '%04o', $perms ) };
}

sub fmmkfile {
    my ( $dir, $newfile, $template ) = @_;

    my $html_safe_dir      = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_newfile  = Cpanel::Encoder::Tiny::safe_html_encode_str($newfile);
    my $html_safe_template = Cpanel::Encoder::Tiny::safe_html_encode_str($template);

    return if _notallowed();

    my $logger = Cpanel::Logger->new();

    $dir = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;

    if ($newfile) {
        $newfile = safefile($newfile);
        $newfile =~ s/\///g;
    }
    else {
        $Cpanel::CPERROR{'fileman'} = "No file specified";
        $logger->warn('No file specified');
        print 'No file specified';
        return;
    }

    if ( !$template ) {
        $logger->info('No template file specified');
        $template = 'Text Document';
    }

    if ( defined $template ) {
        if ( $template =~ m{$DIRECTORY_SEPARATOR} ) {
            $Cpanel::CPERROR{'fileman'} = "Invalid file template name: $html_safe_template";
            print "<br>Invalid file template name:  $html_safe_template";
            return;
        }

        my $open = open( my $th, '<', "$FILE_TEMPLATES_DIRECTORY/$template" );
        if ( !$open ) {
            $Cpanel::CPERROR{'fileman'} = "Unable to open template file $html_safe_template: $!";
            print "<br>Unable to open template file: $html_safe_template";
            return;
        }
    }

    else {
        $template =~ s/\n//g;
    }

    chdir($dir) || do {
        $Cpanel::CPERROR{'fileman'} = "Unable to chdir to $dir: $!";
        $logger->warn("Unable to chdir $dir: $!");
        print "<br>Unable to change directory to $html_safe_dir!  You do not seem to have access permissions! (System Error: $!)\n";
        return;
    };

    my $locale = Cpanel::Locale->get_handle();

    if ( !-e $newfile ) {
        if ( open my $new_fh, '>', $newfile ) {
            if ( open my $tmplt_fh, '<', "$Cpanel::root/share/templates/$template" ) {
                while (<$tmplt_fh>) {
                    print {$new_fh} $_;
                }
                print $locale->maketext( 'Creation of “[_1]” ([_2]) succeeded.', $html_safe_newfile, $html_safe_template );
                close $tmplt_fh;
                close $new_fh;
            }
            else {
                close $new_fh;
                $Cpanel::CPERROR{'fileman'} = "Could not read the template $html_safe_template: $!";
                $logger->warn("Unable to read template $Cpanel::root/share/templates/$template: $!");
                print "$html_safe_template open failed: $!";
                return;
            }
        }
        else {
            $Cpanel::CPERROR{'fileman'} = "Could not open the file $html_safe_newfile: $!";
            $logger->warn("Unable to create $newfile: $!");
            print "$html_safe_newfile open failed: $!";
            return;
        }
    }
    else {
        $Cpanel::CPERROR{'fileman'} = "The file $html_safe_newfile already exists: $!";
        print $locale->maketext( '“[_1]” already exists.', $html_safe_newfile );
        return;
    }
}

sub getfile {
    return if _notallowed(1);

    my ( $dir, $file ) = @_;
    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);
    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    open my $file_fh, '<', $file
      or $logger->die("$html_safe_file open failed: $!");
    while (<$file_fh>) {
        print $_;
    }
    close $file_fh;
    return;
}

sub api2_viewfile {
    my %CFG = @_;
    return if _notallowed(1);
    my $dir  = $CFG{'dir'};
    my $file = $CFG{'file'};
    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);
    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    chdir($dir) || do {
        $Cpanel::CPERROR{'fileman'} = "Unable to change directory to $html_safe_dir! You do not seem to have access permissions! (System Error: $!)";
        return;
    };

    if ( !-f $file ) {
        $Cpanel::CPERROR{'fileman'} = "File \"$html_safe_file\" not found!";
        return;
    }

    my $locale    = Cpanel::Locale->get_handle();
    my $rMIMEINFO = _loadmimeinfo();

    my $filenfo = Cpanel::SafeRun::Errors::saferunnoerror( 'file', '--', $file );
    $filenfo =~ s/^(\S+)://g;

    my %RD = (
        'formatting_before' => '',
        'formatting_after'  => '',
    );

    my $filetype = -d $file ? 'dir' : 'file';
    $RD{'filetype'} = $filetype;
    ( $RD{'mimetype'}, $RD{'mimename'} ) = _getmimename( $dir, $file, $filetype, $rMIMEINFO, 1 );
    $RD{'file'}     = $html_safe_file;
    $RD{'dir'}      = $html_safe_dir;
    $RD{'fileinfo'} = Cpanel::Encoder::Tiny::safe_html_encode_str($filenfo);

    if ( $file =~ /\.tar\.gz$/i || $file =~ /\.tar\.Z$/i || $file =~ /\.tgz$/i ) {
        $RD{'contents'}          = Cpanel::Encoder::Tiny::safe_html_encode_str( scalar Cpanel::SafeRun::Errors::saferunallerrors( Cpanel::Tar::load_tarcfg()->{'bin'}, '-t', '-v', '-z', '-f', $file ) );
        $RD{'formatting_before'} = '<pre>';
        $RD{'formatting_after'}  = '</pre>';

    }
    elsif ( $file =~ /\.tar$/i ) {
        $RD{'contents'}          = Cpanel::Encoder::Tiny::safe_html_encode_str( scalar Cpanel::SafeRun::Errors::saferunallerrors( Cpanel::Tar::load_tarcfg()->{'bin'}, '-t', '-v', '-f', $file ) );
        $RD{'formatting_before'} = '<pre>';
        $RD{'formatting_after'}  = '</pre>';

    }
    elsif ( $filenfo =~ /zip archive/i || $file =~ /\.zip$/i ) {
        $RD{'contents'} = Cpanel::Encoder::Tiny::safe_html_encode_str( scalar Cpanel::SafeRun::Errors::saferunallerrors( 'unzip', '-l', $file ) );
        ;    # was there a reason this was being sent to the shell before??
        $RD{'formatting_before'} = '<pre>';
        $RD{'formatting_after'}  = '</pre>';
    }
    elsif ( $file =~ /\.bz2$/i ) {
        my @bzip2_options = Cpanel::Tar::load_tarcfg()->{'dash_j'} ? ('-j') : ( '--use-compress-program', 'bzip2' );
        $RD{'contents'}          = Cpanel::Encoder::Tiny::safe_html_encode_str( scalar Cpanel::SafeRun::Errors::saferunallerrors( Cpanel::Tar::load_tarcfg()->{'bin'}, '-t', '-v', @bzip2_options, '-f', $file ) );
        $RD{'formatting_before'} = '<pre>';
        $RD{'formatting_after'}  = '</pre>';
    }
    elsif ( $file =~ /\.rpm$/i ) {
        my $rpm    = Cpanel::Binaries::Rpm->new;
        my $result = $rpm->cmd( '-q', '-i', '-p', '--', $file );

        $RD{'contents'}          = Cpanel::Encoder::Tiny::safe_html_encode_str( $result->{'output'} );
        $RD{'formatting_before'} = '<pre>';
        $RD{'formatting_after'}  = '</pre>';
    }
    elsif ( $file =~ /\.d?deb$/i ) {
        my $dpkg  = Cpanel::Binaries::Debian::DpkgDeb->new;
        my $query = eval { $dpkg->query($file) } // '';       # Might not be available on all rhel systems.
        if ($query) {
            $RD{'contents'}          = Cpanel::Encoder::Tiny::safe_html_encode_str($query);
            $RD{'formatting_before'} = '<pre>';
            $RD{'formatting_after'}  = '</pre>';
        }
    }
    elsif ( $filenfo =~ /image/ ) {
        my $mydir = $dir;
        $mydir =~ s/^\/|\/$//g;
        my $myfile = $file;
        $myfile =~ s/^\///g;
        my $uri_encoded_mydir  = Cpanel::Encoder::URI::uri_encode_str($mydir);
        my $uri_encoded_myfile = Cpanel::Encoder::URI::uri_encode_str($myfile);
        $RD{'contents'} = qq(<img name="fmfile" src="$ENV{'cp_security_token'}/viewer/$uri_encoded_mydir/$uri_encoded_myfile" />\n);
    }
    elsif ( $filenfo =~ /text/ ) {
        if ( $file !~ /\.s?html?$/ ) { $RD{'formatting_before'} = "<pre>"; }

        if ( open my $file_fh, '<', $file ) {
            local ($/);
            $RD{'contents'} = Cpanel::Encoder::Tiny::safe_html_encode_str( readline($file_fh) );
            close $file_fh;
        }
        else {
            print "<p>" . Cpanel::Encoder::Tiny::safe_html_encode_str("Error opening $file: $!") . "</p>";
        }
        if ( $file !~ /\.s?html?$/ ) { $RD{'formatting_after'} = "</pre>"; }
    }

    if ( !$RD{'contents'} ) {    # Allows above elsif chain to fall back to here if they couldn't do what they needed.
        my $mydir = $dir;
        $mydir =~ s/^\/|\/$//g;
        my $myfile = $file;
        $myfile =~ s/^\///g;
        my $uri_encoded_mydir  = Cpanel::Encoder::URI::uri_encode_str($mydir);
        my $uri_encoded_myfile = Cpanel::Encoder::URI::uri_encode_str($myfile);
        $RD{'contents'} = qq(<iframe name="fmfile" src="$ENV{'cp_security_token'}/viewer/$uri_encoded_mydir/$uri_encoded_myfile" width="99%" height="90%"></iframe>\n);

    }
    $RD{'formatting_before'} = qq{<div id="file_viewer" style="border: 2px solid #ccc; background: #fff;">} . $RD{'formatting_before'};
    $RD{'formatting_after'} .= "</div>";
    return [ \%RD ];
}

sub viewfile {    ## no critic qw(Subroutines::RequireArgUnpacking)
    return if _notallowed(1);

    my ( $dir, $file ) = @_;
    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);
    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir! You do not seem to have access permissions! (System Error: $!)\n";
        return;
    };

    if ( !-f $file ) {
        print "<br>File \"$html_safe_file\" not found!\n";
        return;
    }

    my $image;
    my $locale = Cpanel::Locale->get_handle();

    my $rMIMEINFO = _loadmimeinfo();
    my ( $mode, $size ) = ( stat($file) )[ 2, 7 ];
    my $filetype = $Cpanel::Fcntl::Types::FILE_TYPES{ $mode & 0170000 };    #& 0170000 = Fcntl::S_IFMT
    my ( $mimeinfo, $mimename ) = _getmimename( $dir, $file, 'file', $rMIMEINFO, 1 );
    $image = $mimename . '.png';

    my $filenfo = Cpanel::SafeRun::Errors::saferunnoerror( 'file', '--', $file );
    $filenfo =~ s/^(\S+)://g;
    my $html_safe_filenfo = Cpanel::Encoder::Tiny::safe_html_encode_str($filenfo);

    my $skipinfo;                                                           # never set ??
    if ( !$skipinfo ) {
        print "<img src=\"../mimeicons/$image\"> <b><font size=+1>$html_safe_file</font></b>\n<br>";
        print $locale->maketext('File Type') . ": $html_safe_filenfo\n<br>";
        print "<hr>";
    }

    print qq{<div id="file_viewer" style="background: #fff;">};

    setpriority( 0, 0, 19 );
    Cpanel::IONice::ionice( 'best-effort', exists $Cpanel::CONF{'ionice_userproc'} ? $Cpanel::CONF{'ionice_userproc'} : 6 );

    # This is going to change the priority for the rest of the time the process runs.
    # In practice this really shouldn't be a problem

    if ( $file =~ /\.tar\.gz$/i || $file =~ /\.tar\.Z$/i || $file =~ /\.tgz$/i ) {
        system_pre( Cpanel::Tar::load_tarcfg()->{'bin'}, '-t', '-v', '-z', '-f', $file );
    }
    elsif ( $file =~ /\.tar$/i ) {
        system_pre( Cpanel::Tar::load_tarcfg()->{'bin'}, '-t', '-v', '-f', $file );
    }
    elsif ( $filenfo =~ /zip archive/i || $file =~ /\.zip$/i ) {
        system_pre( 'unzip', '-l', $file );    # was there a reason this was being sent to the shell before??
    }
    elsif ( $file =~ /\.bz2$/i ) {
        my @bzip2_options = Cpanel::Tar::load_tarcfg()->{'dash_j'} ? ('-j') : ( '--use-compress-program', 'bzip2' );
        system_pre( Cpanel::Tar::load_tarcfg()->{'bin'}, '-t', '-v', @bzip2_options, '-f', $file );
    }
    elsif ( $file =~ /\.rpm$/i ) {
        system_pre( 'rpm', '-q', '-i', '-p', '--', $file );    # was there a reason this was being sent to the shell before??
    }
    elsif ( $filenfo =~ /image/ ) {
        my $mydir = $dir;
        $mydir =~ s/^\/|\/$//g;
        my $myfile = $file;
        $myfile =~ s/^\///g;
        my $uri_encoded_mydir  = Cpanel::Encoder::URI::uri_encode_str($mydir);
        my $uri_encoded_myfile = Cpanel::Encoder::URI::uri_encode_str($myfile);

        print qq(<img name="fmfile" src="$ENV{'cp_security_token'}/viewer/$uri_encoded_mydir/$uri_encoded_myfile" />\n);
    }
    elsif ( $filenfo =~ /text/ ) {
        if ( $file !~ /\.s?html?$/ ) { print "<pre>"; }

        if ( open my $file_fh, '<', $file ) {
            while (<$file_fh>) {
                print Cpanel::Encoder::Tiny::safe_html_encode_str ($_);
            }
            close $file_fh;
        }
        else {
            print "<p>Error opening $html_safe_file: $!</p>";
        }
        if ( $file !~ /\.s?html?$/ ) { print "</pre>"; }
    }
    else {
        my $mydir = $dir;
        $mydir =~ s/^\/|\/$//g;
        my $myfile = $file;
        $myfile =~ s/^\///g;
        my $uri_encoded_mydir  = Cpanel::Encoder::URI::uri_encode_str($mydir);
        my $uri_encoded_myfile = Cpanel::Encoder::URI::uri_encode_str($myfile);
        print qq(<iframe name="fmfile" src="$ENV{'cp_security_token'}/viewer/$uri_encoded_mydir/$uri_encoded_myfile" width="99%" height="90%"></iframe>\n);
    }

    print qq{</div>};

    return;
}

sub extractfile {    ## no critic qw(Subroutines::RequireArgUnpacking)
    return if _notallowed();

    my ( $dir, $file ) = @_;
    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);

    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    my $locale = Cpanel::Locale->get_handle();

    my $rMIMEINFO = _loadmimeinfo();

    my ( $mode, $size ) = ( stat($file) )[ 2, 7 ];
    my $filetype = $Cpanel::Fcntl::Types::FILE_TYPES{ $mode & 0170000 };    #& 0170000 = Fcntl::S_IFMT
    my ( $mimeinfo, $mimename ) = _getmimename( $dir, $file, 'file', $rMIMEINFO, 1 );
    my $image = $mimename . '.png';

    my $filenfo = Cpanel::SafeRun::Errors::saferunnoerror( "file", '--', $file );
    $filenfo =~ s/^(\S+)://g;

    my $html_safe_filenfo = Cpanel::Encoder::Tiny::safe_html_encode_str($filenfo);

    print "<img src=\"../mimeicons/$image\"> <b><font size=+1>$html_safe_file</font></b>\n<br>";
    print $locale->maketext('File Type') . ": $html_safe_filenfo\n<br>";
    print "<hr>";

    _handle_extract( 'display', $file, $dir, $filenfo );
    return;
}

sub _handle_compress {
    my $method      = shift;
    my $filepaths   = shift;
    my $archive     = shift;
    my $archivetype = shift;

    setpriority( 0, 0, 19 );
    Cpanel::IONice::ionice( 'best-effort', exists $Cpanel::CONF{'ionice_userproc'} ? $Cpanel::CONF{'ionice_userproc'} : 6 );

    local $SIG{'PIPE'} = 'IGNORE';

    # This is going to change the priority for the rest of the time the process runs.
    # In practice this really shouldn't be a problem

    my $runner;
    if ( $method eq 'return' ) {
        $runner = sub {
            return Cpanel::SafeRun::Errors::saferunallerrors(@_);
        }
    }
    else {
        $runner = sub {
            system_pre(@_);
        };
    }

    my @relfilelist;
    foreach my $afile ( @{$filepaths} ) {
        my @filep = split( /\//, $afile );
        push @relfilelist, pop(@filep);
    }

    my @buildp = split( /\//, ${$filepaths}[0] );
    pop(@buildp);
    my $builddir = Cpanel::SafeDir::safedir( join( "/", @buildp ) );
    chdir($builddir);

    my @archivep    = split( /\//, $archive );
    my $archivefile = safefile( pop(@archivep) );
    my $compressdir = Cpanel::SafeDir::safedir( join( "/", @archivep ) );
    if ( !-e $compressdir ) {
        Cpanel::SafeDir::MK::safemkdir( $compressdir, '0755' );
    }
    $archive = $compressdir . '/' . $archivefile;

    my $ret;

    if ( -e $archive ) {
        unlink($archive);
    }

    if ( $archivetype eq 'zip' ) {
        $ret = &$runner( 'zip', '-r', $archive, '--', @relfilelist );
    }
    elsif ( $archivetype eq 'tar.gz' || $archivetype eq 'tgz' ) {
        $ret = &$runner( Cpanel::Tar::load_tarcfg()->{'bin'}, '-c', '-v', '-z', '-f', $archive, '--', @relfilelist );
    }
    elsif ( $archivetype eq 'tar.bz2' || $archivetype eq 'tbz' ) {
        my @bzip2_options = Cpanel::Tar::load_tarcfg()->{'dash_j'} ? ('-j') : ( '--use-compress-program', 'bzip2' );
        $ret = &$runner( Cpanel::Tar::load_tarcfg()->{'bin'}, '-c', '-v', @bzip2_options, '-f', $archive, '--', @relfilelist );
    }
    elsif ( $archivetype eq 'tar' ) {
        $ret = &$runner( Cpanel::Tar::load_tarcfg()->{'bin'}, '-c', '-v', '-f', $archive, '--', @relfilelist );
    }
    elsif ( $archivetype eq 'gz' || $archivetype eq 'bz2' ) {
        open( my $ARCHIVE, ">", $archive )
          || return "Could not create archive: $archive: $!";
        open( my $RNULL, "<", "/dev/null" ) or die "Cannot open /dev/null: $!";
        my $gzo;
        my $pid;

        require IO::Handle;
        my $GZR = IO::Handle->new;
        if ( $archivetype eq 'gz' ) {
            $pid = IPC::Open3::open3( "<&" . fileno($RNULL), ">&" . fileno($ARCHIVE), $GZR, 'gzip', '-v', '-c', '--', $relfilelist[0] );
        }
        else {
            $pid = IPC::Open3::open3( "<&" . fileno($RNULL), ">&" . fileno($ARCHIVE), $GZR, 'bzip2', '-v', '-c', '--', $relfilelist[0] );
        }
        while (<$GZR>) {
            if ( $method eq 'return' ) {
                $gzo .= $_;
            }
            else {
                print;
            }
        }
        close($GZR);
        waitpid( $pid, 0 );
        close($ARCHIVE);
        close($RNULL);
        if ( $method eq 'return' ) { return $gzo; }
    }
    else {
        return "Invalid archive type: $archivetype.  No archive created.";
    }

    Cpanel::Quota::reset_cache();
    return $ret;
}

sub _handle_extract {
    my ( $method, $filepath, $extractdir, $filenfo ) = @_;

    setpriority 0, 0, 19;
    Cpanel::IONice::ionice(
        'best-effort',
        exists $Cpanel::CONF{ionice_userproc}
        ? $Cpanel::CONF{ionice_userproc}
        : 6,
    );

    # This is going to change the priority for the rest of the time the process runs.
    # In practice this really shouldn't be a problem

    if ( not $filenfo ) {
        $filenfo = Cpanel::SafeRun::Errors::saferunnoerror( 'file', '--', $filepath );
        $filenfo =~ s/\A \S+ : //xg;
    }

    my $TAR        = Cpanel::Tar::load_tarcfg()->{bin};
    my $runner_ref = sub {
        Cpanel::Quota::reset_cache();
        push @_ => $filepath;
        return $method eq 'return'
          ? Cpanel::SafeRun::Errors::saferunallerrors(@_)
          : system_pre(@_);
    };

    if ( not -d $extractdir ) { Cpanel::SafeDir::MK::safemkdir( $extractdir, '0755' ) }
    chdir $extractdir;

    for ($filepath) {
        return $runner_ref->( $TAR => qw(-x -v -z -f) )
          if / [.] tar [.] (?:gz|Z) \z/xi
          or / [.] tgz              \z/xi;

        return $runner_ref->( $TAR => qw(-x -v -f) )
          if / [.] tar \z/xi;

        return $runner_ref->( unzip => qw(-o -UU) )
          if $filenfo =~ /zip archive/i or / [.] zip \z/xi;

        return $runner_ref->(
            $TAR => qw(-x -v),
            (
                Cpanel::Tar::load_tarcfg()->{dash_j}
                ? qw(-j)
                : qw(--use-compress-program bzip2)
            ),
            '-f',
        ) if / [.] tar [.] bz2 \z/xi or / [.] tbz \z/xi;

        return $runner_ref->(qw(bzip2 -v -d --keep)) if / [.] bz2 \z/xi;
        return $runner_ref->(qw(gzip  -v -d))        if / [.] gz  \z/xi;
    }
    return 'The File Manager does not support extracting this type of archive.';
}

sub emptytrash {
    return if _notallowed(1);

    return if $Cpanel::abshomedir eq '' || $Cpanel::abshomedir eq '/';

    if ( -d "$Cpanel::abshomedir/.trash" ) {
        chdir $Cpanel::abshomedir
          or $logger->die("Could not go into $Cpanel::abshomedir: $!");
        system 'rm', '-rf', '--', "$Cpanel::abshomedir/.trash";
        mkdir "$Cpanel::abshomedir/.trash", 0700;
        Cpanel::Quota::reset_cache();
    }
    else {
        mkdir "$Cpanel::abshomedir/.trash", 0700;
    }
    return;
}

sub installfile {
    my ( $file, $destfile ) = @_;
    return if _notallowed();

    #SHOULD NOT USE SAFEFILE OR WILL BREAK SINCE IT INSTALLS
    #FILES FROM /usr/local/cpanel
    #      $file = safefile($file);
    #      $destfile = safefile($destfile);

    # instead of readin writing line by line which is more code and may break partway we just:
    if ( !-e $destfile ) {
        Cpanel::FileUtils::Copy::safecopy( $file, $destfile );
    }

    if ( $destfile =~ m/\.(?:pl|cgi|php\d*)$/i || $destfile =~ m/\/cgi(email|echo)$/ ) {
        chmod 0755, $destfile;
    }
    else {
        chmod 0644, $destfile;
    }
}

sub newcgifile {
    my ($file) = @_;
    return if _notallowed();

    if ( open my $cgi_fh, '>>', $file ) {
        close $cgi_fh;
        chmod 0755, $file or $logger->die("Could not chmod $file: $!");
    }
    else {
        $logger->die("Could not touch $file: $!");
    }
    return;
}

sub suexecperm {
    return if _notallowed();

    my $file = shift;
    if ( !-e apache_paths_facade->bin_suexec() ) {
        chmod 0666, $file or $logger->die("chmod $file failed: $!");
    }
    else {
        chmod 0644, $file or $logger->die("chmod $file failed: $!");
    }
    return;
}

sub delfile {
    my ( $dir, $file ) = @_;

    return if _notallowed();

    if ( !length $file ) {
        print "<br>The \"file\" parameter is required\n";
        return;
    }

    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);

    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };

    mkdir "$Cpanel::abshomedir/.trash", 0700
      or $logger->die("making .trash failed: $!")
      if !-d "$Cpanel::abshomedir/.trash";

    Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::abshomedir/.trash/.trash_restore");
    chmod( 0600, "$Cpanel::abshomedir/.trash/.trash_restore" );

    my $trash_restore_fh;
    my $trashlock = Cpanel::SafeFile::safeopen( $trash_restore_fh, '+<', "$Cpanel::abshomedir/.trash/.trash_restore" )
      or $logger->die("delfile failed: $!");

    my $trash_restore_map = _read_restore_map($trash_restore_fh);
    seek( $trash_restore_fh, 0, 2 );    #2=SEEK_END

    my $destfile = $file;
    my $i        = 0;
    while ( $trash_restore_map->{$destfile} || -e "$Cpanel::abshomedir/.trash/$destfile" ) {
        $i++;
        $destfile = $file . '.' . $i;
    }
    rename( $file, "$Cpanel::abshomedir/.trash/$destfile" ) || do {
        Cpanel::SafeFile::safeclose( $trash_restore_fh, $trashlock );
        die "Failed to move '$html_safe_file' to trash (System Error: $!)\n";
    };
    print $trash_restore_fh _escape_file_names_for_restore_map($destfile) . '=' . _escape_file_names_for_restore_map("$dir/$file") . "\n";
    Cpanel::SafeFile::safeclose( $trash_restore_fh, $trashlock );

    return 1;
}

sub restore_file {
    my ( $trash_dir, $file_to_restore ) = @_;

    return if _notallowed();

    $trash_dir       = $trash_dir ? Cpanel::SafeDir::safedir($trash_dir) : "$Cpanel::abshomedir/.trash";
    $file_to_restore = safefile($file_to_restore);

    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($trash_dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file_to_restore);

    my $trash_restore_fh;
    my $trashlock = Cpanel::SafeFile::safeopen( $trash_restore_fh, '+<', "$trash_dir/.trash_restore" ) or do {
        $logger->warn("Restore file failed, unable to read mapping file (.trash_restore): $!");
        die "Restore file failed, unable to read mapping file (.trash_restore): $!\n";
    };

    my $trash_restore_map = _read_restore_map($trash_restore_fh);
    if ( my $restore_path = $trash_restore_map->{$file_to_restore} ) {
        if ( -e $restore_path ) {
            Cpanel::SafeFile::safeclose( $trash_restore_fh, $trashlock );
            $logger->warn("Unable to restore '$html_safe_dir/$html_safe_file'! File is already present on the filesystem.");
            die "Unable to restore '$html_safe_file'! File is already present on the filesystem.\n";
        }
        if ( !_is_path_within_dir( $restore_path, $Cpanel::abshomedir ) ) {
            Cpanel::SafeFile::safeclose( $trash_restore_fh, $trashlock );
            $logger->warn("Unable to restore '$html_safe_dir/$html_safe_file'! Restore path is outside of user's homedir - '$restore_path'.");
            die "Unable to restore '$html_safe_file'! Restore path is outside of user's homedir.\n";
        }
        rename( "$Cpanel::abshomedir/.trash/$file_to_restore", $restore_path ) || do {
            Cpanel::SafeFile::safeclose( $trash_restore_fh, $trashlock );
            die "Failed to restore '$html_safe_file'! System Error: $!\n";
        };
        delete $trash_restore_map->{$file_to_restore};
    }
    else {
        Cpanel::SafeFile::safeclose( $trash_restore_fh, $trashlock );
        die "Unable to restore '$html_safe_file'! File is not present within the .trash_restore map.\n";
    }

    # update the .trash_restore file
    my @new_restore_file_contents;
    foreach my $filename_in_trash ( keys %{$trash_restore_map} ) {
        push @new_restore_file_contents, _escape_file_names_for_restore_map($filename_in_trash) . '=' . _escape_file_names_for_restore_map( $trash_restore_map->{$filename_in_trash} ) . "\n";
    }
    Cpanel::SafeFile::Replace::safe_replace_content( $trash_restore_fh, $trashlock, \@new_restore_file_contents );
    Cpanel::SafeFile::safeclose( $trash_restore_fh, $trashlock );

    return 1;
}

sub _escape_file_names_for_restore_map {
    my $file = shift;

    # Escape the '=' and '\n' characters, as they can break the 'restore'
    # functionality due to how the .trash_restore map is read and updated.
    $file =~ s/=/____EQUALS____/g;
    $file =~ s/\n/____NEWLINE____/g;
    return $file;
}

sub _unescape_file_names_for_restore_map {
    my $file = shift;
    $file =~ s/____EQUALS____/=/g;
    $file =~ s/____NEWLINE____/\n/g;
    return $file;
}

# Reads the content for the filehandle passed, and returns a hashref
#
# Input : A safeopen'ed filehandle to read from
# Output: A hashref that maps the 'file name in the .trash directory' to 'the path of deleted file'
#
# Note: This function assumes that the filehandle opening/closing is handled by the caller
sub _read_restore_map {
    my $trash_fh    = shift;
    my $restore_map = {};
    while ( my $line = readline $trash_fh ) {
        chomp $line;
        my ( $file, $orig ) = split( /=/, $line, 2 );
        $file = _unescape_file_names_for_restore_map($file);
        $restore_map->{$file} = _unescape_file_names_for_restore_map($orig);
    }
    return $restore_map;
}

# Checks to see if the path specified is within the base path specified
#
# Input: Positional arguments for
#   $path - the path to check
#   $base_path - the base path that $path should be under
#
# Examples:
#   _is_path_within_dir('/root/dir', '/root') returns true;
#   _is_path_within_dir('/home/user1/public_html', '/home/user2/') returns false;
#
sub _is_path_within_dir {
    my $path      = shift;
    my $base_path = shift;

    # ignore relative paths - we should not use relative paths in any of the file maps we generate.
    return if $path =~ m{\.\.};

    if ( $path =~ m/^$base_path/ ) {
        return 1;
    }

    return;
}

sub realdelfile {
    my ( $dir, $file ) = @_;
    return if _notallowed();

    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);
    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };
    unlink $file or $logger->die("removing $html_safe_file failed: $!");
    return;
}

sub fmsavehtmlfile {
    return if _notallowed();

    #FIXME: xss insecure
    # local $Cpanel::IxHash::Modify = 'none'; needs done so that $page is raw... -> handled by expvar call in cpanel.pl 2149
    my ( $dir, $file, $page, $doubledecode ) = @_;

    if (
        $doubledecode
        || (   $Cpanel::FORM{'doubledecode'}
            && $Cpanel::FORM{'doubledecode'} eq '1' )
    ) {

        #doubledecode is DOUBLE URI ENCODING not html ENCODING
        $dir  = Cpanel::Encoder::URI::uri_decode_str($dir);
        $file = Cpanel::Encoder::URI::uri_decode_str($file);
    }

    $dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : $Cpanel::abshomedir;
    $file = safefile($file);

    my $html_safe_dir  = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);
    my $html_safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    chdir($dir) || do {
        print "<br>Unable to change directory to $html_safe_dir!  You do not " . "seem to have access permissions! (System Error: $!)\n";
        return;
    };
    $page =~ s/\r//g;

    my $hashead;
    my $hasbody;

    open my $of_fh, '<', $file
      or $logger->die("Could not open $html_safe_file: $!");
    while (<$of_fh>) {
        $hashead = 1 if /(\<[\s\t]*\/[\s\t]*head[^\>]*\>)/i;
        if (/(.*\<[\s\t]*body[^\>]*\>)/i) {
            $hasbody = 1;
            last;
        }
    }
    seek( $of_fh, 0, 0 );

    my $intop    = 1;
    my $inbottom = 0;
    my $top      = '';
    my $bottom   = '';

    while (<$of_fh>) {
        while (/<BASE.*CPTAG[^\>]+\>/) {
            s/<BASE.*CPTAG[^\>]+\>//gi;
        }

        if ($intop) {
            s/\<[\s\t]*\![\s\t]*\-[^\>]+\>[\r\n]*//g;
            if ($hasbody) {
                if (/(.*\<[\s\t]*body[^\>]*\>)/i) {
                    $top .= $1;
                    $intop = 0;
                }
                else {
                    $top .= $_;
                }
            }
            else {
                if (/(.*\<[\s\t]*\/[\s\t]*head[^\>]*\>)/i) {
                    $top .= $1;
                    $intop = 0;
                }
                else {
                    $top .= $_;
                }
            }
        }
        elsif ( $inbottom == 0 ) {
            if (/(\<[\s\t]*\/[\s\t]*body[^\>]*\>.*)/i) {
                $bottom .= $1;
                $inbottom = 1;
            }
        }
        else {
            $bottom .= $_;
        }
    }

    $top = '<html>' if $intop;
    close $of_fh;

    open my $file_fh, '>', $file
      or $logger->die("Could not open $html_safe_file: $!");
    print {$file_fh} $top;
    print {$file_fh} $page;
    print {$file_fh} $bottom;
    print {$file_fh} "\n";
    if (   ( $dir =~ /(www|public_html)[\/]*$/ )
        && $file =~ /^\d+\.shtml/
        && ( length($page) < 600 ) ) {
        print {$file_fh} "\n<!-- \n";
        print {$file_fh} " " x int( 600 - length($page) );
        print {$file_fh} "\n--> \n";
    }
    close $file_fh;
    return;
}

sub safefile {

    # Cleans up the file name passed so it does not contain illegal characters
    # Arguments:
    #   $file - string - unsafe file name
    # Returns:
    #   string - safe version of the file name.

    my ($file) = @_;
    $file =~ s/[\/<>;\0]//g;
    return $file;
}

sub safepath {

    # Cleans up the path passed
    # Arguments:
    #   $path - string - unsafe path name
    # Returns:
    #   string - safe version of the path name.

    my $path = shift;
    chop($path) if substr( $path, -1 ) eq '/';
    if ( $path eq $Cpanel::homedir || $path eq $Cpanel::abshomedir ) {
        return $Cpanel::abshomedir;
    }

    my @SL   = split( /\//, $path );
    my $file = pop(@SL);
    return Cpanel::SafeDir::safedir( join( '/', @SL ) ) . '/' . $file;
}

sub _notallowed {

    # Test if the called function can be run based on the rules for that function
    # NOTES:
    #   1) Ugly inverted logic...
    # Arguments:
    #   $ok_in_demo - boolean - Defaults to false, skip the demo check for this one
    #   $ok_without_feature - boolean - Default to false, skip the feature check for this routine
    # Returns:
    #   bool - returns 1 if not allowed and 0 if allowed

    Cpanel::Server::Type::Role::FileStorage->verify_enabled();

    my $ok_in_demo         = shift || 0;
    my $ok_without_feature = shift || 0;

    if ( !main::hasfeature('filemanager') && !$ok_without_feature ) {
        $Cpanel::CPERROR{'fileman'} = "This feature cannot be used";
        return 1;
    }

    if ( defined $Cpanel::CPDATA{'DEMO'} && $Cpanel::CPDATA{'DEMO'} eq '1' && !$ok_in_demo ) {
        $Cpanel::CPERROR{'fileman'} = "This feature cannot be used in demo mode";
        return 1;
    }

    return 0;
}

sub system_pre {
    print "<pre>\n";
    Cpanel::SafeRun::Dynamic::livesaferun(
        'prog'      => \@_,
        'formatter' => sub {
            return Cpanel::Encoder::Tiny::safe_html_encode_str( $_[0] );
        },
    );
    print "</pre>\n";
}

sub api2_search {

    # Search for matching entries based on the arguments
    # Arguments:
    #  recursive - bool - defaults 1 - do a recursive search
    #  mimeinfo  - bool - defaults 1 - include mime info.
    #
    # Returns:
    #  string[] - list of file objects
    #    ->{'file'} - string - path to the file

    my %args = @_;

    if ( !defined $args{'recursive'} ) {
        $args{'recursive'} = 1;
    }
    if ( !defined $args{'mimeinfo'} ) {
        $args{'mimeinfo'} = 1;
    }

    my @result = search(%args);

    foreach my $result_obj (@result) {
        $result_obj->{'file'} = $result_obj->{'path'};
        delete $result_obj->{'path'};
    }

    return @result;
}

my %_ATTRIBUTE_INDICES = (    #things that get returned directly from stat
    'size'  => 7,
    'atime' => 8,
    'mtime' => 9,
    'ctime' => 10,
);

sub search {
    my (%CFG) = @_;

    # Search for matching entries based on the arguments.
    # Arguments:
    #  recursive - bool - defaults 1 - do a recursive search
    #  mimeinfo  - bool - defaults 1 - include mime info.
    #  dir       - string -
    #  regex     - string -
    #  attributes - string - | delimited string of attributes to return
    #    user
    #    group
    #    type
    #
    #
    # Returns:
    #  string[] - list of file objects
    #    ->{'path'} - string - path to the file

    my (@RSD);
    return (@RSD) if ( _notallowed() );
    my $dir   = Cpanel::SafeDir::safedir( $CFG{'dir'} );
    my $regex = $CFG{'regex'};

    my $rMIMEINFO;
    my $return_mime = $CFG{'mimeinfo'};
    if ($return_mime) {
        $rMIMEINFO = _loadmimeinfo();
    }

    local $SIG{'__WARN__'} = 'DEFAULT';

    my $stat_indices_ar;    #do not create an array unless we have to
    my $attribute_labels_ar;
    my $return_user;
    my $return_group;
    my $return_usage;
    my $return_type;
    my $return_mode;
    if ( defined $CFG{'attributes'} ) {
        my @attrs      = split m{\|}, $CFG{'attributes'};
        my %attributes = map { $_ => $_ATTRIBUTE_INDICES{$_} } @attrs;
        $attribute_labels_ar = [ keys %attributes ];
        $stat_indices_ar     = [ values %attributes ];

        $return_user  = exists $attributes{'user'};
        $return_group = exists $attributes{'group'};
        $return_usage = exists $attributes{'usage'};
        $return_type  = exists $attributes{'type'};
        $return_mode  = exists $attributes{'mode'};
    }

    my $gid_cacheref_hr;
    if ($return_group) {
        $gid_cacheref_hr = Cpanel::PwCache::GID::get_gid_cacheref();
    }

    my $attributes_func_string = q{};
    if ($stat_indices_ar) {
        $attributes_func_string .= '@return_hash{ @{$attribute_labels_ar} } = @stat[ @{$stat_indices_ar} ];';

        if ($return_user) {
            $attributes_func_string .= q/$return_hash{'user'} = Cpanel::PwCache::getpwuid( $stat[4] );/;
        }
        if ($return_group) {
            $attributes_func_string .= q/$return_hash{'group'} = $gid_cacheref_hr->{ $stat[5] }->[0];/;
        }
        if ($return_usage) {
            $attributes_func_string .= q/$return_hash{'usage'} = $stat[12] * 512;/;
        }
        if ($return_type) {
            $attributes_func_string .= q/$return_hash{'type'} = $filetype;/;
        }
        if ($return_mode) {
            $attributes_func_string .= q/$return_hash{'mode'} = Fcntl::S_IMODE( $stat[2] );/;
        }
    }
    if ($return_mime) {
        $attributes_func_string .= q/my ( $mimetype, $mimename ) = _getmimename( $dir, $file, $filetype, $rMIMEINFO );/ . q/$return_hash{'mimeinfo'} = $mimename;/;
    }

    if ( $CFG{'recursive'} ) {
        Cpanel::SafeFind::find(
            {
                'wanted' => sub {
                    my @PATH = split( /\//, $_ );
                    my $file = pop(@PATH);
                    if ( $file ne q{.} && $file ne q{..} && ( !$regex || $file =~ m/$regex/ ) ) {
                        my @stat     = lstat $_;
                        my $filetype = $Cpanel::Fcntl::Types::FILE_TYPES{ $stat[2] & 0170000 };    #& 0170000 = Fcntl::S_IFMT
                        my $dir      = join( '/', @PATH );

                        my %return_hash = ( 'path' => $dir . '/' . $file );

                        if ($attributes_func_string) {
                            eval $attributes_func_string;
                        }

                        push( @RSD, \%return_hash );
                    }

                    #return value is ignored
                },
                'no_chdir' => 1
            },
            $dir,
        );
    }
    else {
        if ( opendir my $dh, $dir ) {
            my @files = readdir $dh;
            close $dh;

            my $matched_files_ar =
              $regex
              ? [ grep { $_ =~ m{$regex} } @files ]
              : \@files;
            for my $file ( @{$matched_files_ar} ) {
                if ( $file ne q{.} && $file ne q{..} ) {
                    my $path     = "$dir/$file";
                    my @stat     = lstat $path;
                    my $filetype = $Cpanel::Fcntl::Types::FILE_TYPES{ $stat[2] & 0170000 };    #& 0170000 = Fcntl::S_IFMT

                    my %return_hash = ( 'path' => $path );

                    if ($attributes_func_string) {
                        eval $attributes_func_string;
                    }

                    push( @RSD, \%return_hash );
                }
            }
        }
    }

    return @RSD;
}

sub api2_getedittype {
    my (%CFG) = @_;
    my (@RSD);

    my $dir   = $CFG{'dir'};
    my $file  = $CFG{'file'};
    my $path  = safepath( $dir . '/' . $file );
    my $finfo = Cpanel::SafeRun::Simple::saferun( 'file', '--', $path );
    my $ftype = 'text';

    $CFG{'editor'} //= '';

    if ( $finfo =~ /cpp|c\+\+/i && $CFG{'editor'} eq 'editarea' ) {
        $ftype = 'cpp';
    }
    if ( $finfo =~ /javascript/i ) {
        $ftype = ( $CFG{'editor'} eq 'editarea' ? 'js' : 'javascript' );
    }
    elsif ( $finfo =~ /java/i ) {
        $ftype = 'java';
    }
    elsif ( $finfo =~ /perl/i ) {
        $ftype = 'perl';
    }
    elsif ( $finfo =~ /vbs/i ) {
        $ftype = ( $CFG{'editor'} eq 'editarea' ? 'vb' : 'vbscript' );
    }
    elsif ( $finfo =~ /php/i ) {
        $ftype = 'php';
    }
    elsif ( $finfo =~ /(style|sheet|css)/i ) {
        $ftype = 'css';
    }
    elsif ( $finfo =~ /sql/i ) {
        $ftype = 'sql';
    }
    elsif ( $finfo =~ /html/i ) {
        $ftype = 'html';
    }
    elsif ( $finfo =~ /pas/i && $CFG{'editor'} eq 'editarea' ) {
        $ftype = 'pas';
    }
    elsif ( $finfo =~ /python/i && $CFG{'editor'} eq 'editarea' ) {
        $ftype = 'python';
    }
    elsif ( $finfo =~ /xml/i && $CFG{'editor'} eq 'editarea' ) {
        $ftype = 'xml';
    }

    if ( $ftype eq 'text' ) {
        my @types = (
            [ qr/\.js$/,                 [ 'js', 'javascript' ] ],
            [ qr/\.vbs$/,                [ 'vb', 'vbscript' ] ],
            [ qr/\.java$/,               'java' ],
            [ qr/\.p[lm]$/,              'perl' ],
            [ qr/\.(?:shtml|html|htm)$/, 'html' ],
            [ qr/\.sql$/,                'sql' ],
            [ qr/\.cpp$/,                'cpp' ],
            [ qr/\.c$/,                  'c' ],
            [ qr/\.bas$/,                'basic' ],
            [ qr/\.py$/,                 'python' ],
            [ qr/\.xml$/,                'xml' ],
            [ qr/\.rb$/,                 'ruby' ],
            [ qr/\.php$/,                'php' ],
            [ qr/\.css$/,                'css' ],
        );
        foreach my $set (@types) {
            my ( $re, $type ) = @$set;
            if ( $path =~ $re ) {
                $ftype = ref $type ? ( $CFG{'editor'} eq 'editarea' ? $type->[0] : $type->[1] ) : $type;
                last;
            }
        }
    }

    my @edit_area_types = qw(basic brainfuck c cpp css html js pas perl php python ruby sql vb xml);
    my @ace_types       = qw(asp csharp css html java javascript perl php ruby sql text vbscript);

    if ( $CFG{'editor'} eq 'editarea' ) {
        if ( !grep( /^$ftype$/, @edit_area_types ) ) {
            $ftype = '';
        }
    }
    else {
        if ( !grep( /^$ftype$/, @ace_types ) ) {
            $ftype = 'generic';
        }
    }

    push( @RSD, { 'type' => $ftype } );
    return @RSD;
}

sub api2_fileop {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my (%CFG) = @_;

    my @RSD;

    my @srcfiles;
    my @destfiles;
    if ( $Cpanel::FORM{'multiform'} ) {    #do not split on , since , can be in a file
        @srcfiles  = ( $Cpanel::FORM{'sourcefiles'} );
        @destfiles = ( $Cpanel::FORM{'destfiles'} );
    }
    else {
        @srcfiles  = split( /\,/, $CFG{'sourcefiles'} || $Cpanel::FORM{'sourcefiles'} );
        @destfiles = split( /\,/, $CFG{'destfiles'}   || $Cpanel::FORM{'destfiles'} );
    }
    foreach my $key ( keys %Cpanel::FORM ) {
        if ( $key =~ /^sourcefiles-/ ) { push @srcfiles, $Cpanel::FORM{$key} }
    }
    foreach my $key ( keys %Cpanel::FORM ) {
        if ( $key =~ /^destfiles-/ ) { push @destfiles, $Cpanel::FORM{$key} }
    }
    my $op       = $CFG{'op'}       || $Cpanel::FORM{'op'};
    my $metadata = $CFG{'metadata'} || $Cpanel::FORM{'metadata'};
    if ( $Cpanel::FORM{'doubledecode'} ) {

        #doubledecode is DOUBLE URI ENCODING not html ENCODING
        $metadata = Cpanel::Encoder::URI::uri_decode_str($metadata);
        my $i = 0;
        foreach (@srcfiles) {
            $srcfiles[$i] = Cpanel::Encoder::URI::uri_decode_str( $srcfiles[$i] );
            $i++;
        }
        $i = 0;
        foreach (@destfiles) {
            $destfiles[$i] = Cpanel::Encoder::URI::uri_decode_str( $destfiles[$i] );
            $i++;
        }
    }

    # Provide early error return if a source
    # and destination both must be supplied.
    my $early_result;
    if ( $op =~ m/^(?:move)$/ ) {
        if ( !scalar @srcfiles ) {
            $early_result = {
                'err'    => 'Source must be supplied.',
                'result' => 0,
            };
        }
        if ( !scalar @destfiles ) {
            my $msg = 'Destination must be supplied.';
            if ( ref $early_result ) {
                $early_result->{'err'} .= " $msg";
            }
            else {
                $early_result = {
                    'err'    => $msg,
                    'result' => 0,
                };
            }
        }
    }

    return $early_result if $early_result;

    for my $i ( 0 .. $#srcfiles ) {
        if ( defined $destfiles[$i] ) {
            if ( $destfiles[$i] =~ m{^/} ) {
                $destfiles[$i] = safepath( $destfiles[$i] );
            }
            else {
                my $fulldest = $srcfiles[$i];
                $fulldest =~ s{[^/]*\z}{$destfiles[$i]};
                $destfiles[$i] = safepath($fulldest);
            }
        }
        $srcfiles[$i] = safepath( $srcfiles[$i] );
    }

    if ( ( $op eq 'move' ) && ( scalar @destfiles == 1 ) && ( scalar @srcfiles > 1 ) && ( !-d $destfiles[0] ) ) {
        return {
            err    => 'Multiple sources may not be moved to a non-directory destination.',
            result => 0,
        };
    }

    Cpanel::LoadModule::lazy_load_module('File::Copy::Recursive');
    local $File::Copy::Recursive::CPRFComp = 1;

    for my $i ( 0 .. $#srcfiles ) {
        if ( !defined $destfiles[$i] || length $destfiles[$i] == 0 ) { $destfiles[$i] = $destfiles[0]; }

        if (    # Make sure the operator is not a source only operator
               $op ne 'trash'
            && $op ne 'chmod'
            && $op ne 'unlink'
            && $op ne 'extract'

            # Then check if the files provided in source and destination
            # are correct.
            && ( ( -d $destfiles[$i] && _isindir( $srcfiles[$i], $destfiles[$i] ) )
                || $destfiles[$i] eq $srcfiles[$i] )
        ) {
            push(
                @RSD,
                {
                    'src'    => $srcfiles[$i],
                    'dest'   => $destfiles[$i],
                    'err'    => 'Source and Destination are the Same',
                    'result' => 0
                }
            );
            next;
        }

        if ( $op eq 'compress' ) {
            my $results = _handle_compress( 'return', \@srcfiles, $destfiles[$i], $metadata );
            push(
                @RSD,
                {
                    'src'    => $srcfiles[$i],
                    'dest'   => $destfiles[$i],
                    'output' => $results,
                    'result' => 1
                }
            );
            last();
        }
        elsif ( $op eq 'extract' ) {
            my $results = _handle_extract( 'return', $srcfiles[$i], $destfiles[$i] );
            push(
                @RSD,
                {
                    'src'    => $srcfiles[$i],
                    'dest'   => $destfiles[$i],
                    'output' => $results,
                    'result' => 1
                }
            );
        }
        elsif ( $op eq 'move' ) {
            my $move_ok = 0;

            # First, determine the new filename, in case the destination
            # is a directory rather than a file.
            my $dfile = $destfiles[$i];
            if ( -d $dfile ) {
                $srcfiles[$i] =~ m{/([^/]+)\z};
                $dfile .= "/$1";
                $dfile =~ tr{/}{}s;
            }

            # Next, perform the move.
            #
            # If rename() fails because of any of these conditions, fall back
            # to using File::Copy::Recursive:
            #  1) the destination is a populated directory, or
            #  2) the destination exists on a different device.
            #
            # If it fails for any other reason, do *not* try again, because
            # making a copy will only succeed where rename() failed if we're
            # trying to move across devices.  Otherwise, File::Copy::Recursive
            # will still fail and might remove data due to a hard-to-fix bug.
            #
            # Note: In case 1, directory contents will be merged into the
            # destination dir, where existing files will be overwritten by
            # files from the source dir in the event of a name conflict.
            if ( rename( $srcfiles[$i], $dfile ) ) {
                $move_ok = 1;
            }
            elsif ( $!{'EXDEV'} || -d $dfile ) {
                $move_ok = 1 if File::Copy::Recursive::rmove( $srcfiles[$i], $destfiles[$i] );
            }

            if ($move_ok) {
                push(
                    @RSD,
                    {
                        'src'    => $srcfiles[$i],
                        'dest'   => $destfiles[$i],
                        'result' => 1
                    }
                );
            }
            else {
                $Cpanel::CPERROR{'fileman'} = $!;
                push(
                    @RSD,
                    {
                        'src'    => $srcfiles[$i],
                        'dest'   => $destfiles[$i],
                        'err'    => $!,
                        'result' => 0
                    }
                );
            }
        }
        elsif ( $op eq 'unlink' ) {
            Cpanel::LoadModule::load_perl_module('File::Path');

            my @DF    = split( /\//, $srcfiles[$i] );
            my $tfile = pop(@DF);
            my $tdir  = join( '/', @DF );
            next if ( Cwd::abs_path( $tdir . '/' . $tfile ) eq $Cpanel::abshomedir );

            # If attempting to unlink() fails with EISDIR, this must be a directory.
            my $status = unlink( $tdir . '/' . $tfile );
            if ( !$status && $! == EISDIR ) {

                # If attempting to rmdir() fails with ENOTEMPTY or EEXIST, it must not be empty.
                $status = rmdir( $tdir . '/' . $tfile );
                if ( !$status && ( $! == ENOTEMPTY || $! == EEXIST ) ) {

                    # Trying to handle simple cases through File::Path::remove_tree() caused CPANEL-34513.
                    # Reserve it for the complicated case of being unable to remove a nested directory tree.
                    my $error_ar;
                    $status = File::Path::remove_tree( $tdir . '/' . $tfile, { safe => 1, error => \$error_ar } );

                    # remove_tree() doesn't set $!; instead, a value for $! must be parsed out of $error_ar.
                    # The solution being used here is that under all(?) circumstances not covered by the previous
                    # cases, remove_tree() could not have emptied the target directory. Therefore, it is always
                    # appropriate to return ENOTEMPTY. This should at least hint to the user that going into
                    # the directory to delete things may be helpful in discovering the cause of the problem.
                    $! = ENOTEMPTY if !$status;    ## no critic qw(RequireLocalizedPunctuationVars)
                }
            }

            if ( $status || !-e $tdir . '/' . $tfile ) {
                push(
                    @RSD,
                    {
                        'src'    => $srcfiles[$i],
                        'dest'   => $destfiles[$i],
                        'result' => 1
                    }
                );
                Cpanel::Quota::reset_cache();
            }
            else {
                $Cpanel::CPERROR{'fileman'} = $!;
                push(
                    @RSD,
                    {
                        'src'    => $srcfiles[$i],
                        'dest'   => $destfiles[$i],
                        'err'    => $!,
                        'result' => 0
                    }
                );
            }
        }
        elsif ( $op eq 'trash' ) {
            my @DF    = split( /\//, $srcfiles[$i] );
            my $tfile = pop(@DF);
            my $tdir  = join( '/', @DF );

            if ( delfile( $tdir, $tfile ) ) {
                push(
                    @RSD,
                    {
                        'src'    => $srcfiles[$i],
                        'dest'   => $destfiles[$i],
                        'result' => 1
                    }
                );
            }
            else {
                $Cpanel::CPERROR{'fileman'} = $!;
                push(
                    @RSD,
                    {
                        'src'    => $srcfiles[$i],
                        'dest'   => $destfiles[$i],
                        'err'    => $!,
                        'result' => 0
                    }
                );
            }
        }
        elsif ( $op eq 'restorefile' ) {
            my @DF    = split( /\//, $srcfiles[$i] );
            my $tfile = pop(@DF);
            my $tdir  = join( '/', @DF );
            my $result;
            eval { $result = restore_file( $tdir, $tfile ); };
            if ( !$@ ) {
                push(
                    @RSD,
                    {
                        'src'    => $srcfiles[$i],
                        'dest'   => $destfiles[$i],
                        'result' => $result,
                    }
                );
            }
            else {
                chomp $@;
                $Cpanel::CPERROR{'fileman'} = $@;
                push(
                    @RSD,
                    {
                        'src'    => $srcfiles[$i],
                        'dest'   => $destfiles[$i],
                        'err'    => $@,
                        'result' => 0
                    }
                );
            }
        }
        elsif ( $op eq 'chmod' ) {
            my $result = 1;
            my $err    = "";
            if ( $metadata !~ /^[0-7]{3,4}$/ ) {
                $result = 0;
                $err    = 'Invalid filesystem permissions specified';
            }
            else {
                $result = chmod oct($metadata), $srcfiles[$i];
                $err    = $!;
            }
            my $rhash = {
                'src'    => $srcfiles[$i],
                'dest'   => $destfiles[$i],
                'result' => $result,
            };
            if ( !$result ) {
                $Cpanel::CPERROR{'fileman'} = $err;
                $rhash->{'err'} = $err;
            }
            push @RSD, $rhash;
        }
        elsif ( $op eq 'rename' ) {
            my $result = 1;
            my $err    = "";
            if ( -e $destfiles[$i] ) {
                $result = 0;
                $err    = 'Destination already exists';
            }
            else {
                $result = rename $srcfiles[$i], $destfiles[$i];
                $err    = $!;
            }
            my $rhash = {
                'src'    => $srcfiles[$i],
                'dest'   => $destfiles[$i],
                'result' => $result,
            };
            if ( !$result ) {
                $rhash->{'err'} = $err;
                $Cpanel::CPERROR{'fileman'} = $err;
            }
            push @RSD, $rhash;
        }
        elsif ( $op eq 'copy' ) {
            if ( File::Copy::Recursive::rcopy( $srcfiles[$i], $destfiles[$i] ) ) {
                push(
                    @RSD,
                    {
                        'src'    => $srcfiles[$i],
                        'dest'   => $destfiles[$i],
                        'result' => 1
                    }
                );
                Cpanel::Quota::reset_cache();
            }
            else {
                $Cpanel::CPERROR{'fileman'} = $!;
                push(
                    @RSD,
                    {
                        'src'    => $srcfiles[$i],
                        'dest'   => $destfiles[$i],
                        'err'    => $!,
                        'result' => 0
                    }
                );
            }
        }
        elsif ( $op eq 'link' ) {
            if ( link( $srcfiles[$i], $destfiles[$i] ) ) {
                push(
                    @RSD,
                    {
                        'src'    => $srcfiles[$i],
                        'dest'   => $destfiles[$i],
                        'result' => 1
                    }
                );
            }
            else {
                $Cpanel::CPERROR{'fileman'} = $!;
                push(
                    @RSD,
                    {
                        'src'    => $srcfiles[$i],
                        'dest'   => $destfiles[$i],
                        'err'    => $!,
                        'result' => 0
                    }
                );
            }
        }
        else {
            $Cpanel::CPERROR{'fileman'} = "Unknown operation sent to api2_fileop";
            push @RSD, { 'result' => 0, 'err' => $Cpanel::CPERROR{'fileman'} };
        }
    }

    return @RSD;
}

sub api2_getdiskinfo {
    my $res_ref = Cpanel::Quota::getdiskinfo();
    return [$res_ref];
}

sub api2_getabsdir {
    my %OPTS = @_;
    return [ { 'absdir' => ( Cwd::abs_path( $OPTS{'dir'} ) || $OPTS{'dir'} ) } ];

}

sub _isindir {
    my ( $path, $dir ) = @_;
    my @P = split( /\//, $path );
    pop(@P);
    my $filedir = join( '/', @P );
    if ( Cwd::abs_path($filedir) eq Cwd::abs_path($dir) ) {
        return 1;
    }
    return 0;
}

sub api2_autocompletedir {
    my %OPTS = @_;

    my $result = Cpanel::API::wrap_deprecated( 'Fileman', 'autocompletedir', \%OPTS );
    return $result->data;
}

my $filemanager_feature_allow_demo = {
    needs_feature => "filemanager",
    xss_checked   => 1,
    modify        => 'none',
    allow_demo    => 1,
};

my $filemanager_feature_deny_demo = {
    needs_feature => "filemanager",
    xss_checked   => 1,
    modify        => 'none',
};

my $xss_checked_modify_none_allow_demo = {
    xss_checked => 1,
    modify      => 'none',
    allow_demo  => 1,
};

our %API = (
    'getabsdir'       => $xss_checked_modify_none_allow_demo,
    'getfileactions'  => $filemanager_feature_allow_demo,
    'search'          => $xss_checked_modify_none_allow_demo,
    'getdiractions'   => $filemanager_feature_allow_demo,
    'getdir'          => $xss_checked_modify_none_allow_demo,
    'autocompletedir' => $xss_checked_modify_none_allow_demo,    # Wrapped Cpanel::API::Fileman::autocompletedir
    'viewfile'        => {
        %$filemanager_feature_allow_demo,
        'csssafe' => 1,
    },
    'statfiles'   => $xss_checked_modify_none_allow_demo,
    'getpath'     => { allow_demo => 1 },
    'fileop'      => $filemanager_feature_deny_demo,
    'getdiskinfo' => {
        'csssafe'  => 1,
        allow_demo => 1
    },
    'uploadfiles' => {                                           # Wrapped Cpanel::API::Fileman::upload_files
        %$filemanager_feature_deny_demo,
        'engine' => 'hasharray',
        'func'   => 'api2_uploadfiles',
    },
    'listfiles'   => $filemanager_feature_allow_demo,            # Wrapped Cpanel::API::Fileman::list_files
    'getedittype' => $filemanager_feature_deny_demo,
    'savefile'    => $xss_checked_modify_none_allow_demo,        # Wrapped Cpanel::API::Fileman::save_file_content
    'mkdir'       => $filemanager_feature_deny_demo,
    'mkfile'      => $filemanager_feature_deny_demo,
);

$_->{'needs_role'} = 'FileStorage' for values %API;

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

## Re-factored and relocated functions
# These are not used from the Cpanel::Fileman namespace anywhere in the current code base
# These are left here for possible 3rd party usage

sub restorefiles {
    Cpanel::LoadModule::load_perl_module('Cpanel::Backups');
    goto \&Cpanel::Backups::restorefiles;
}

sub restoredb {
    Cpanel::LoadModule::load_perl_module('Cpanel::Backups');
    goto \&Cpanel::Backups::restoredb;
}

sub restoreaf {
    Cpanel::LoadModule::load_perl_module('Cpanel::Backups');
    goto \&Cpanel::Backups::restoreaf;
}

sub restorefile {
    Cpanel::LoadModule::load_perl_module('Cpanel::Backups');
    goto \&Cpanel::Backups::restorefile;
}

sub fullbackup {
    Cpanel::LoadModule::load_perl_module('Cpanel::Backups');
    goto \&Cpanel::Backups::fullbackup;
}

sub listfullbackups {
    Cpanel::LoadModule::load_perl_module('Cpanel::Backups');
    goto \&Cpanel::Backups::listfullbackups;
}

*safedir = *Cpanel::SafeDir::safedir;

*makecleandir = *Cpanel::SafeDir::safedir;

*display_uri = *Cpanel::Encoder::URI::uri_encode_dirstr;

## Re-factored and relocated functions so they can be used by both
## API1, API2 and UAPI
*_loadmimeinfo       = *Cpanel::Fileman::Mime::get_mime_type_map;
*_load_mimename_data = *Cpanel::Fileman::Mime::load_mimename_data;
*_getmimename        = *Cpanel::Fileman::Mime::get_mime_type;

1;
