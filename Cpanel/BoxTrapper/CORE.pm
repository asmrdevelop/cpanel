package Cpanel::BoxTrapper::CORE;

# cpanel - Cpanel/BoxTrapper/CORE.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
# Boxtrapper Backend Functions
# NO UI (html)
#
# *** PLEASE DO NOT LOAD LOCALE IN THIS MODULE ***
# *** THIS IS INTENDED TO BE LIGHTWEIGHT FOR   ***
# *** bin/boxtrapper SINCE IT IS EXECUTED FOR  ***
# *** EVERY DELIVERY *****************************
#

use strict;

## no critic qw(RequireUseWarnings) # TODO: CPANEL-35175 - make this use warnings.pm

use Cpanel::Imports;

use IO::Handle                           ();
use MIME::Base64                         ();
use Cpanel::Config::LoadConfig           ();
use Cpanel::Exception                    ();
use Cpanel::PwCache                      ();
use Cpanel::PwCache::CurrentUser         ();
use Cpanel::Config::LoadCpUserFile       ();
use Cpanel::LoadModule                   ();
use Cpanel::Config::Httpd::Perms         ();
use Cpanel::Domain::Local                ();
use Cpanel::Encoder::Tiny                ();
use Cpanel::Encoder::utf8                ();
use Cpanel::FileUtils::TouchFile         ();
use Cpanel::Hostname                     ();
use Cpanel::AdminBin::Serializer         ();
use Cpanel::AdminBin::Serializer::FailOK ();
use Cpanel::Logger                       ();
use Cpanel::MailLoopProtect              ();
use Cpanel::Rand                         ();
use Cpanel::Rand::Get                    ();
use Cpanel::Regex                        ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::SafeFile                     ();
use Cpanel::StringFunc::Case             ();
use Cpanel::StringFunc::Match            ();
use Cpanel::StringFunc::Trim             ();
use Cpanel::FileUtils::Write             ();

=encoding utf8

=head1 NAME

C<Cpanel::BoxTrapper::CORE.pm>

=head1 DESCRIPTION

This module contains methods for working with core BoxTapper features.

=head1 FUNCTIONS

=cut

our $VERSION = '2.6';
our $suexec;

my $logger = Cpanel::Logger->new();

our $SKIP_EMAIL_DIR_CHECKS    = 1;
our $PERFORM_EMAIL_DIR_CHECKS = 0;
our $SKIP_CREATE_EMAIL_DIRS   = 1;
our $CREATE_EMAIL_DIRS        = 0;

my ( %mailuser, %ACCOUNT_INFO_CACHE, $loaded_pwcache, %HOMEDIR_CACHE, %HOMEDIR_OK_CACHE );

sub _role_is_enabled {
    require Cpanel::Server::Type::Role::MailReceive;

    if ( !eval { Cpanel::Server::Type::Role::MailReceive->verify_enabled(); 1 } ) {
        $Cpanel::CPERROR{'boxtrapper'} = $@->to_locale_string_no_id();
        return undef;
    }

    return 1;
}

# Provides both API1 and UAPI error behavior depending on the presence of the $opts flags.
# When $opts is not defined, it falls back to api1 behavior. You can pass either a string
# or a Cpanel::Exception.
sub _handle_error {
    my ( $error, $opts ) = @_;

    my $output;
    if ( UNIVERSAL::isa( $error, 'Cpanel::Exception' ) ) {
        $output = $error->to_string();
    }
    else {
        $output = $error;
    }

    if ( $opts->{api1} ) {
        $Cpanel::CPERROR{'boxtrapper'} = $output;
        print Cpanel::Encoder::Tiny::safe_html_encode_str($output) . "\n";
    }
    elsif ( $opts->{uapi} ) {
        die Cpanel::Exception->create_raw($output);
    }
    return;
}

# Provides both API1 and UAPI warn behavior depending on the presence of the $opts flags.
sub _handle_warn {
    my ( $error, $log, $opts ) = @_;

    my $output;
    if ( UNIVERSAL::isa( $error, 'Cpanel::Exception' ) ) {
        $output = $error->to_string();
    }
    else {
        $output = $error;
    }

    logger()->warn($log);
    if ( $opts->{api1} ) {
        $Cpanel::CPERROR{'boxtrapper'} = $output;
    }
    elsif ( $opts->{uapi} ) {
        die Cpanel::Exception->create_raw($output);    # for UAPI we will always throw too
    }
    return;
}

sub BoxTrapper_initvars {
    if ( _role_is_enabled() ) {
        if ( !scalar keys %mailuser ) {
            %mailuser = BoxTrapper_getmailuser();
        }
    }

    return;
}

*BoxTrapper_getranddata = *Cpanel::Rand::Get::getranddata;

=head2 BoxTrapper_addaddytolist(LIST, ADDY, DIR, OPTS)

Add an email address to the specified list.

=head3 ARGUMENTS

=over

=item LIST - string

List name to add the email to.

May be one of the following:

=over

=item * white

=item * black

=item * ignore

=back

=item ADDY - string

Email address to add to the list.

=item DIR - string

Directory where email is stored.

=item OPTS - hashref

Used to control output handling.

=back

=cut

sub BoxTrapper_addaddytolist {
    my ( $list, $addy, $dir, $opts ) = @_;
    $opts = {} if $opts;

    return if !_role_is_enabled();
    return if _is_demo();
    return if !$addy;
    return if !$dir;
    return if !grep { $_ eq $list } qw(black white ignore);

    # Chars to escape: . @ { }
    $addy =~ s/$Cpanel::Regex::regex{'singledot'}/\\\./g;
    $addy =~ s/$Cpanel::Regex::regex{'commercialat'}/\\\@/g;
    $addy =~ s/\{/\\\{/g;
    $addy =~ s/\}/\\\}/g;

    $addy =~ s/$Cpanel::Regex::regex{'newline'}//g;
    $addy =~ s/^\s*|\s*$//g;

    $dir  =~ s/$Cpanel::Regex::regex{'doubledot'}//g;
    $list =~ s/$Cpanel::Regex::regex{'doubledot'}//g;

    return if ( $addy eq '' );

    my $list_path = $dir . '/.boxtrapper/' . $list . '-list.txt';
    if ( -e $list_path ) {
        my $listlock = Cpanel::SafeFile::safeopen( my $MYLST, '<', $list_path );
        if ( !$listlock ) {
            _handle_warn(
                locale()->maketext( "The system could not read from “[_1]”.", $list_path ),
                "The system could not read from $list_path.",
                $opts,
            );
            return;
        }
        while (<$MYLST>) {
            chomp();
            if ( $_ eq 'from ' . $addy ) {
                Cpanel::SafeFile::safeclose( $MYLST, $listlock );
                BoxTrapper_clog( 2, $dir, "The address '$addy' already exists on the list '$list'" );
                return 1;
            }
        }
        Cpanel::SafeFile::safeclose( $MYLST, $listlock );
    }

    my $listlock = Cpanel::SafeFile::safeopen( my $MYLST, '>>', $list_path );
    if ( !$listlock ) {
        _handle_warn(
            locale()->maketext( "The system could not write to “[_1]”.", $list_path ),
            "The system could not write to $list_path.",
            $opts,
        );
        return;
    }
    print $MYLST "from $addy\n";
    Cpanel::SafeFile::safeclose( $MYLST, $listlock );

    BoxTrapper_clog( 3, $dir, "The address '$addy' was added to the '$list' list" );

    return 1;
}

sub BoxTrapper_checkdeadq {
    my ( $emaildir, $rconf ) = @_;

    return if _is_demo();

    return if !_role_is_enabled();

    my $now      = time();
    my $killtime = $rconf->{'stale-queue-time'};
    $killtime = ( $killtime * 86400 );    #time in seconds

    my $mtime = ( stat("$emaildir/boxtrapper/last_dead_check") )[9];

    return if ( ( $mtime + 86400 ) > $now && $mtime < $now );    #time warp safe
                                                                 # case 47038: only check once per day
                                                                 # the period was being calculated at 2*stale-queue-time previously
    BoxTrapper_clog( 2, $emaildir, "Searching for stale data files ($killtime seconds old)" );
    my @DIRS = qw( boxtrapper/queue boxtrapper/verifications boxtrapper/log );
    my $file_mtime;
    my @removed_queue_files;
    foreach my $dir (@DIRS) {
        if ( opendir my $qf_fh, $emaildir . '/' . $dir ) {
            my @QFS = readdir $qf_fh;
            closedir $qf_fh;
            foreach my $qf ( grep { !m/^\./ } @QFS ) {
                $file_mtime = ( $dir eq 'boxtrapper/queue' && $qf =~ tr/-// ) ? ( split( /[\-\.]/, $qf ) )[1] : ( stat( $emaildir . '/' . $dir . '/' . $qf ) )[9];

                # The mtime should be retrieved from the filename if possible in order to avoid
                # the problem in case 47038
                if ( ( $file_mtime + $killtime ) < $now ) {
                    if ( unlink $emaildir . '/' . $dir . '/' . $qf ) {
                        push @removed_queue_files, $qf if $dir eq 'boxtrapper/queue';
                        BoxTrapper_clog( 2, $emaildir, "Unlinking ${emaildir}/${dir}/${qf} age exceeds $killtime seconds" );
                    }
                    else {
                        BoxTrapper_clog( 2, $emaildir, "Failed to unlink ${emaildir}/${dir}/${qf}: $!" );
                    }
                }
            }
        }
    }
    Cpanel::FileUtils::TouchFile::touchfile("$emaildir/boxtrapper/last_dead_check");
    if (@removed_queue_files) {
        BoxTrapper_removefromsearchdb( $emaildir, \@removed_queue_files );
    }

    return;
}

sub BoxTrapper_checklist {    ## no critic qw(ProhibitExcessComplexity ProhibitManyArgs)
    my ( $list, $dir, $addy, $raddyto, $raddycc, $subject ) = @_;

    return if !_role_is_enabled();

    $dir  =~ s/$Cpanel::Regex::regex{'doubledot'}//g;
    $list =~ s/$Cpanel::Regex::regex{'doubledot'}//g;
    $list =~ s/\///g;
    my $list_mtime       = ( stat( $dir . '/.boxtrapper/' . $list . '-list.txt' ) )[9];
    my $list_cache_mtime = ( stat( $dir . '/.boxtrapper/' . $list . '-list.txt.cache' ) )[9];
    return if !$list_mtime;

    my $now = time();
    my $list_ref;
    if ( $list_mtime < $list_cache_mtime && $list_cache_mtime < $now && open( my $cache_fh, '<', $dir . '/.boxtrapper/' . $list . '-list.txt.cache' ) ) {
        $list_ref = Cpanel::AdminBin::Serializer::FailOK::LoadFile($cache_fh);
        close($cache_fh);
    }

    if ( !defined $list_ref || !ref $list_ref || $list_ref->{'VERSION'} != $VERSION ) {

        # Ensure that we don’t have stale entries.
        $list_ref = {};

        my $linenum = 0;
        my $list_fh;
        if ( my $list_lock = Cpanel::SafeFile::safeopen( $list_fh, '<', $dir . '/.boxtrapper/' . $list . '-list.txt' ) ) {
            my ( $header, $match, $matchrgx );
            while ( readline $list_fh ) {
                $linenum++;
                next if /^#/;
                s/\r?\n$//;

                ( $header, $match ) = split( / /, $_, 2 );
                next if ( !defined $match || $match =~ m/^\s*$/ );
                $header = Cpanel::StringFunc::Case::ToLower($header);

                $matchrgx = $match;
                if ( $match =~ /^'/ || $match =~ /'$/ ) {
                    $match =~ s/^\'//;
                    $match =~ s/\'$//;
                    $matchrgx = '\Q' . $match . '\E';
                }
                elsif ( $match =~ /^"/ || $match =~ /"$/ ) {
                    $match =~ s/^\"//;
                    $match =~ s/\"$//;
                    $matchrgx = '\Q' . $match . '\E';
                }
                else {
                    $matchrgx = $match;
                }

                # Prevent broken regexes from passing through
                my $regex;

                eval {

                    # Treat warnings as fatal so that we skip anything
                    # suspicious-looking.
                    local $SIG{'__WARN__'} = sub { die( shift() ) };

                    $regex = qr{$matchrgx};
                };

                if ( !$regex ) {
                    warn "Skipping failed regexp ($matchrgx): $@";
                    next;
                }

                $list_ref->{$header}{$match} = $linenum;
            }
            $list_ref->{'VERSION'} = $VERSION;
            my $cache_file = $dir . '/.boxtrapper/' . $list . '-list.txt.cache';
            unless ( Cpanel::FileUtils::Write::overwrite( $cache_file, Cpanel::AdminBin::Serializer::Dump($list_ref), 0600 ) ) {
                unlink $cache_file;    #outdated
            }
            Cpanel::SafeFile::safeclose( $list_fh, $list_lock );
        }
        else {
            Cpanel::Logger::cplog( "Failed to open $dir/.boxtrapper/${list}-list.txt: $!", 'warn', __PACKAGE__, 1 );
            return;
        }
    }
    foreach my $header ( 'from', 'subject', 'to', 'cc' ) {

        # This can be problematic if Perl decides to warn() on something
        # in our regexp. With the whole regexp on a single line,
        # the warn() will contain that entire regexp. That means a large
        # chunk of output goes to Exim’s log, which makes Exim get nervous
        # and send boxtrapper a SIGKILL. We could try to work around this
        # by putting newlines in, escaping whitespace in the regexp, and
        # defining the regexp with the /x modifier, but that would be risky.
        my $regex_all = join( '|', keys %{ $list_ref->{$header} } ) || next;
        my $regex     = qr{($regex_all)};
        if ( $header eq 'from' ) {
            if ( $addy =~ $regex ) {
                my $match   = $1;
                my $linenum = $list_ref->{$header}{$match};
                if ( !$linenum ) {
                    foreach my $key ( keys %{ $list_ref->{$header} } ) {
                        if ( $addy =~ /$key/ ) {
                            $linenum = $list_ref->{$header}{$key};
                            last;
                        }
                    }
                }

                BoxTrapper_logmatch( $dir, $list, $header, $match, $linenum );
                return wantarray ? ( 1, $match, $linenum, $header ) : 1;
            }
        }
        elsif ( $header eq 'subject' ) {
            if ( $subject =~ $regex ) {
                my $match   = $1;
                my $linenum = $list_ref->{$header}{$match};
                if ( !$linenum ) {
                    foreach my $key ( keys %{ $list_ref->{$header} } ) {
                        if ( $subject =~ /$key/ ) {
                            $linenum = $list_ref->{$header}{$key};
                            last;
                        }
                    }
                }
                BoxTrapper_logmatch( $dir, $list, $header, $match, $linenum );
                return wantarray ? ( 1, $match, $linenum, $header ) : 1;
            }
        }
        elsif ( $header eq 'to' ) {
            foreach my $addyto ( @{$raddyto} ) {
                if ( $addyto =~ $regex ) {
                    my $match   = $1;
                    my $linenum = $list_ref->{$header}{$match};
                    if ( !$linenum ) {
                        foreach my $key ( keys %{ $list_ref->{$header} } ) {
                            if ( $addyto =~ /$key/ ) {
                                $linenum = $list_ref->{$header}{$key};
                                last;
                            }
                        }
                    }
                    BoxTrapper_logmatch( $dir, $list, $header, $match, $linenum );
                    return wantarray ? ( 1, $match, $linenum, $header ) : 1;
                }
            }
        }
        elsif ( $header eq 'cc' ) {
            foreach my $addycc ( @{$raddycc} ) {
                if ( $addycc =~ $regex ) {
                    my $match   = $1;
                    my $linenum = $list_ref->{$header}{$match};
                    if ( !$linenum ) {
                        foreach my $key ( keys %{ $list_ref->{$header} } ) {
                            if ( $addycc =~ /$key/ ) {
                                $linenum = $list_ref->{$header}{$key};
                                last;
                            }
                        }
                    }
                    BoxTrapper_logmatch( $dir, $list, $header, $match, $linenum );
                    return wantarray ? ( 1, $match, $linenum, $header ) : 1;
                }
            }
        }
    }

    return;
}

sub BoxTrapper_cleanlist {
    my ( $file, $opts ) = @_;
    $opts = {} if !$opts;

    return if !_role_is_enabled();
    return if _is_demo();

    my @LIST;
    my $listlock = Cpanel::SafeFile::safeopen( my $LIST_FH, '+<', $file );
    if ( !$listlock ) {
        $logger->warn("Could not edit $file");
        return 0;
    }

    my %DUPLIST;
    while ( my $line = <$LIST_FH> ) {
        $line = Cpanel::StringFunc::Trim::ws_trim($line);

        if ( $line =~ /^\s*(from|to|cc)\s+/i ) {
            my ( $match, $address ) = split( /\s+/, $line, 2 );
            if (   Cpanel::StringFunc::Match::beginmatch( $address, '*' )
                || Cpanel::StringFunc::Match::beginmatch( $address, '+' )
                || Cpanel::StringFunc::Match::beginmatch( $address, '?' ) ) {
                $address = '.' . $address;

                # people like to put things like *@cpanel.net when
                # its a perl regex and they really mean .*@cpanel.net
            }

            $match = lc($match);
            next if ( $DUPLIST{$match}{$address} );
            $DUPLIST{$match}{$address} = 1;
            push( @LIST, $match . ' ' . $address );
        }
        else {
            push( @LIST, $line );
        }
    }
    seek( $LIST_FH, 0, 0 );
    print $LIST_FH join( "\n", @LIST ) . "\n";
    truncate( $LIST_FH, tell($LIST_FH) );
    Cpanel::SafeFile::safeclose( $LIST_FH, $listlock );

    return 1;
}

sub BoxTrapper_clog {
    my ( $loglevel, $emaildir, $log ) = @_;

    return if !_role_is_enabled();

    return if _is_demo();

    my ( $mon, $mday, $year ) = BoxTrapper_nicedate( time() );
    chomp $log;

    local $Cpanel::Logger::ENABLE_BACKTRACE = 0;

    if ( !-e $emaildir . '/boxtrapper/log' ) {
        if ( !Cpanel::SafeDir::MK::safemkdir( $emaildir . '/boxtrapper/log', '0700' ) ) {
            $logger->info( "Could not create dir \"" . $emaildir . '/boxtrapper/log' . "\": $!" );
            return;
        }
    }
    my $loglock = Cpanel::SafeFile::safeopen( \*CLOG, '>>', $emaildir . '/boxtrapper/log/' . $mon . '-' . $mday . '-' . $year . '.log' );
    if ( !$loglock ) {
        $logger->warn("Could not write to $emaildir/boxtrapper/log/$mon\-$mday\-$year\.log");
        return;
    }
    else {

        #Do NOT use encode('UTF-8', ...) in compiled code. (cf. FB 137797)
        utf8::encode($log) if utf8::is_utf8($log);
        print CLOG $log . "\n";
        Cpanel::SafeFile::safeclose( \*CLOG, $loglock );
    }
    return;
}

sub BoxTrapper_delivermessage {    ## no critic qw(ProhibitExcessComplexity ProhibitManyArgs)
    my ( $account, $deliver_to_system, $emaildir, $file, $hdref, $bdref ) = @_;

    return if !_role_is_enabled();

    return if _is_demo();

    my $fwd = 0;

    $file =~ s/$Cpanel::Regex::regex{doubledot}//g;

    # These will be nearly identical, but sometimes not 100% identical
    my ( @mbox_additions, @fwd_additions );

    my @FWDLIST;
    if ($deliver_to_system) {
        @FWDLIST = BoxTrapper_loadfwdlist($emaildir);
        if ( $#FWDLIST > -1 && -x '/usr/sbin/sendmail' ) {
            $fwd = 1;
            BoxTrapper_clog( 3, $emaildir, "Forward list is active to: " . join( ',', @FWDLIST ) );
        }
    }

    push @mbox_additions, @{$hdref};
    if ($fwd) {
        if ( $hdref->[0] =~ /^From\s+/ ) {
            push @fwd_additions, "X-Boxtrapper: " . BoxTrapper_getourid($emaildir) . "\n";
            push @fwd_additions, @{$hdref}[ 1 .. $#$hdref ];
        }
        else {
            push @fwd_additions, @{$hdref};
        }
    }
    push @mbox_additions, "\n";
    push @fwd_additions,  "\n";
    if ( ref $bdref eq 'GLOB' ) {
        my $buffer;
        while ( read( $bdref, $buffer, 32768 ) ) {
            push @mbox_additions, $buffer;
            push @fwd_additions,  $buffer;
        }
        close($bdref);
    }
    elsif ( !ref $bdref || $#{$bdref} == -1 ) {
        my $buffer;
        while ( read( STDIN, $buffer, 32768 ) ) {
            push @mbox_additions, $buffer;
            push @fwd_additions,  $buffer;
        }
    }
    else {
        push @mbox_additions, @{$bdref};
        push @fwd_additions,  @{$bdref};
    }

    # Done assembling data; begin attempting to actually commit changes to disk.

    my $msglock;
    my $orig_umask = umask(0007);    # Keep perms consistent with Exim

    my $mbox_fh;

    # subaddressing suppport for boxtrapper
    my @addresses = (
        Cpanel::BoxTrapper::CORE::BoxTrapper_extractaddresses( Cpanel::BoxTrapper::CORE::BoxTrapper_splitaddresses( Cpanel::BoxTrapper::CORE::BoxTrapper_getheader( 'to', $hdref ) ) ),
        Cpanel::BoxTrapper::CORE::BoxTrapper_extractaddresses( Cpanel::BoxTrapper::CORE::BoxTrapper_splitaddresses( Cpanel::BoxTrapper::CORE::BoxTrapper_getheader( 'cc', $hdref ) ) )
    );
    my $my_addresses;
    my $subaddress;
    foreach my $address (@addresses) {
        if ( $address =~ s{\+([^@]+)}{} ) {
            $subaddress = $1;
            $my_addresses ||= _get_addresses_for_account( $account, $emaildir );
            if ( $my_addresses->{$address} ) { last; }    # matched
        }
    }

    # All I/O (including open, print, and close) must be checked in case disk quota is exceeded.
    # The way to do this is to immediately die inside this eval if any I/O we care about fails.
    # This will cause a warning, any necessary cleanup, and the function to return undef instead
    # of 1. This return value should be checked by callers.
    eval {

        # /usr/libexec/dovecot/dovecot-lda -f [FROM](the message) -d [RECIPIENT]
        if ($deliver_to_system) {
            open( $mbox_fh, '|-' ) || exec( '/usr/libexec/dovecot/dovecot-lda', '-d', $account, ( $subaddress ? ( '-m', "INBOX.$subaddress" ) : () ) );
        }
        else {
            $msglock = Cpanel::SafeFile::safeopen( $mbox_fh, '>>', $file )
              or die "Unable to open mailbox '$file' for writing: $!\n";
        }

        # Both print() and flush() must be checked for failure. Do not split this into separate lines
        # without ensuring both of these are still checked.
        print {$mbox_fh} @mbox_additions and $mbox_fh->flush() or die "Failed to write mbox data: $!\n";

        if ($deliver_to_system) {
            close $mbox_fh or do {
                my $err = $!;
                Cpanel::LoadModule::load_perl_module('Cpanel::ChildErrorStringifier');
                die "close dovecot-lda: $err: " . 'Cpanel::ChildErrorStringifier'->new($?)->autopsy();
            };
        }
        else {
            Cpanel::SafeFile::safeclose( $mbox_fh, $msglock ) or die "safeclose: $!\n";
            $msglock = undef;
        }

        umask($orig_umask);

        if ($fwd) {
            foreach my $forward (@FWDLIST) {
                my $fwd_fh = IO::Handle->new;
                open( $fwd_fh, '|-' ) || exec( '/usr/sbin/sendmail', '-i', '--', $forward );
                my $status = print {$fwd_fh} @fwd_additions;
                $status &&= $fwd_fh->flush;
                close $fwd_fh;
                unless ($status) {
                    die "Failed to write fwd data: $!\n";
                }
            }
        }
    };
    my $err = $@;

    umask($orig_umask);

    Cpanel::SafeFile::safeunlock($msglock) if $msglock;

    if ($err) {
        warn $err;
        return;
    }

    return 1;
}

sub BoxTrapper_extractaddress {
    my $email = shift;

    return if !_role_is_enabled();

    $email = Cpanel::StringFunc::Case::ToLower($email);
    $email =~ s/$Cpanel::Regex::regex{'multipledot'}/$Cpanel::Regex::regex{'singledot'}/g;
    my ($ea) = $email =~ m/\<($Cpanel::Regex::regex{'emailaddr'})\>/;
    if ( !$ea ) {
        ($ea) = $email =~ m/($Cpanel::Regex::regex{'emailaddr'})/;
    }
    return $ea;
}

sub BoxTrapper_extractaddresses {
    return map { BoxTrapper_extractaddress($_) } @_;
}

# Warning, this extracts binary attachments as well.
sub BoxTrapper_extractall {
    my $filename = shift;
    my $limit    = shift;
    return if !$filename;

    return if !_role_is_enabled();

    my @body;
    my $headers_ref = [];
    if ( open my $msg_fh, '<', $filename ) {
        $headers_ref = _getheaders_from_fh($msg_fh);
        if ($limit) {
            my $buffer;
            read( $msg_fh, $buffer, $limit );
            @body = map { $_ . "\n" } split( /\n/, $buffer );
        }
        else {
            @body = <$msg_fh>;
        }
        close($msg_fh);
    }
    else {
        Cpanel::Logger::cplog( "Failed to open $filename: $!", 'warn', __PACKAGE__, 1 );
    }
    return wantarray ? ( $headers_ref, \@body ) : \@body;
}

# Warning, this extracts binary attachments as well.
sub BoxTrapper_extract_headers_return_bodyglobref {
    my $filename = shift;
    return if !$filename;

    return if !_role_is_enabled();

    if ( open my $msg_fh, '<', $filename ) {
        my $headers_ref = _getheaders_from_fh($msg_fh);
        return ( $headers_ref, $msg_fh );
    }

    Cpanel::Logger::cplog( "Failed to open $filename: $!", 'warn', __PACKAGE__, 1 );
    return ( [], undef );
}

sub BoxTrapper_extractbody {
    my (@args) = @_;

    return if !_role_is_enabled();

    my $body_aref = BoxTrapper_extractall(@args);
    if ( $body_aref && ref $body_aref eq 'ARRAY' ) {
        return wantarray ? @{$body_aref} : join( '', @{$body_aref} );
    }
    return;
}

sub BoxTrapper_findreturnaddy {
    my ( $account, $okaddys, @ALLADDYS ) = @_;

    return if !_role_is_enabled();

    my @OKADDYS = split( /\,/, $okaddys );

    foreach my $okaddy (@OKADDYS) {
        foreach my $emailaddy (@ALLADDYS) {
            if ( $okaddy eq $emailaddy ) {
                return $okaddy;
            }
        }
    }

    if ( @OKADDYS && $OKADDYS[0] =~ /\@/ ) {
        return $OKADDYS[0];
    }

    return $account;
}

=head2 BoxTrapper_getaccountinfo(ACCOUNT, HOMEDIR, OPTS)

Gets information about the account.

=head3 ARGUMENTS

=over

=item ACCOUNT - string

Either a cpanel user name or an email account.

When OPTS->{validate_ownership} is true:

=over

=item - the cpanel user must be the current logged in user

=item - the email account must be on a domain that is owned by the current cpanel user

=back

=item HOMEDIR - string

Optional, if not provided, it will be looked up automatically.

=item OPTS - hashref

=over

=item api1 - boolean

Provides error handing and output using api1 system. (print, Cpanel::CPERROR)

=item uapi - boolean

Provide error handling by throwing exceptions

=item validate - boolean

When true, will validate ownership of the passed email and if it exists on the system. When false or missing, these validations are skipped.

=back

=back

=head3 RETURNS

(HOMEDIR, DOMAIN) list where:

=over

=item HOMEDIR - string

the home directory for the email account

=item DOMAIN - string

the domain portion of the account if present

=back

=head3 EXCEPTIONS

=over

=item When the email is in an unrecognized format.

=item When the account information can not be retrieved.

=item When the domain for the email account is not owned by the current cPanel user.

=item When the email account does not exist.

=item There may be other less common exceptions generated as well.

=back

=cut

sub BoxTrapper_getaccountinfo {
    my ( $account, $homedir, $opts ) = @_;
    $opts = {} if !$opts;

    return if !_role_is_enabled();

    # Case 94497
    if ( $account =~ /\0/ ) {
        Cpanel::Logger::cplog( 'Invalid account', 'warn', __PACKAGE__, 1 );
        _handle_error(
            locale()->maketext( 'The system is unable to locate the account information for “[_1]”.', $account ),
            $opts,
        );
        return;
    }

    if ( exists $ACCOUNT_INFO_CACHE{$account} ) {
        return @{ $ACCOUNT_INFO_CACHE{$account} };
    }
    if ( !$loaded_pwcache ) {
        $loaded_pwcache = 1;
        Cpanel::PwCache::CurrentUser::prime_cache();
    }

    my ( $mailbox, $domain );
    if ( $account =~ $Cpanel::Regex::regex{'commercialat'} ) {
        ( $mailbox, $domain ) = split( /\@/, $account );
    }
    elsif ( $account =~ $Cpanel::Regex::regex{'plussign'} ) {
        ( $mailbox, $domain ) = split( /\+/, $account );
    }
    elsif ( $opts->{validate} && $account eq $Cpanel::user ) {
        return @{ $ACCOUNT_INFO_CACHE{$account} = [ ( Cpanel::PwCache::getpwnam($account) )[7], '' ] };
    }
    elsif ( $opts->{validate} && $account ne $Cpanel::user ) {
        _handle_error(
            locale()->maketext( 'The system could not locate the account information for “[_1]”.', $account ),
            $opts,
        );
        return;
    }
    elsif ( !$opts->{validate} && $account ) {
        return @{ $ACCOUNT_INFO_CACHE{$account} = [ ( Cpanel::PwCache::getpwnam($account) )[7], '' ] };
    }
    else {
        _handle_error(
            locale()->maketext( 'The system did not recognize the format for “[_1]” when looking up the account.', $account ),
            $opts,
        );
        return;
    }

    if ( !$domain ) {
        _handle_error(
            locale()->maketext( 'The system is unable to locate the account information for “[_1]”.', $account ),
            $opts,
        );
        return;
    }

    if ( $opts->{validate} ) {

        # Validate the domain is owned by the current user
        my $user_owns_domain = eval {
            require Cpanel::AcctUtils::DomainOwner;
            Cpanel::AcctUtils::DomainOwner::is_domain_owned_by(
                $domain,
                $Cpanel::user,
            );
        };
        if ( my $exception = $@ ) {
            _handle_error( $exception, $opts );
            return;
        }
        elsif ( !$user_owns_domain ) {
            _handle_error(
                locale()->maketext(
                    'The [asis,cPanel] user, “[_1]” does not own the requested account “[_2]”.',
                    $Cpanel::user,
                    $account
                ),
                $opts,
            );
            return;
        }

        require Cpanel::Email::Exists;
        Cpanel::Email::Exists::pop_exists_or_die( $mailbox, $domain );
    }

    if ($homedir) {
        return @{ $ACCOUNT_INFO_CACHE{$account} = [ $homedir, $domain ] };
    }

    my $homedir2 = BoxTrapper_gethomedir($domain);
    return @{ $ACCOUNT_INFO_CACHE{$account} = [ $homedir2, $domain ] };
}

sub BoxTrapper_getdomainowner {
    my $domain = shift;

    return if !_role_is_enabled();

    my $domainowner;

    BoxTrapper_initvars();

    if ( $> == $mailuser{'uid'} ) {
        if ( -r '/etc/userdomains' ) {
            if ( open my $ud_fh, '<', '/etc/userdomains' ) {
                while ( readline $ud_fh ) {
                    if (m/^\Q$domain\E\s*:\s*(\S+)/) {
                        $domainowner = $1;
                        last;
                    }
                }
                close $ud_fh;
            }
        }
        elsif ( -e _ ) {
            Cpanel::Logger::cplog( "System file /etc/userdomains does not exist. Run /usr/local/cpanel/scripts/updateuserdomains", 'warn', __PACKAGE__, 1 );
        }
        elsif ( !-r _ ) {
            Cpanel::Logger::cplog( "/etc/userdomains is not readable by $mailuser{'name'}", 'warn', __PACKAGE__, 1 );
        }
    }
    else {
        $domainowner = ( Cpanel::PwCache::getpwuid($>) )[0];
    }
    if ( !$domainowner ) {
        Cpanel::Logger::cplog( "Unable to determine owner of domain $domain", 'warn', __PACKAGE__, 1 );
    }
    return $domainowner;
}

sub BoxTrapper_getemaildirs {
    my ( $account, $homedir, $no_checks, $no_create, $opts ) = @_;
    $opts = {} if !$opts;

    return if !_role_is_enabled();

    return if !$no_create && _is_demo();

    if ( !$account ) {
        Cpanel::Logger::cplog( 'Missing argument(s)', 'warn', __PACKAGE__, 1 );
        _handle_error( locale()->maketext( 'Email directory for account “[_1]” does not exist.', $account ), $opts );
        return;
    }
    elsif ( !$homedir ) {
        $homedir = ( Cpanel::PwCache::getpwuid($>) )[7];
    }

    $account =~ s/$Cpanel::Regex::regex{'multipledot'}/\./g;
    $homedir =~ s/$Cpanel::Regex::regex{'multipledot'}/\./g;

    if ( exists $HOMEDIR_OK_CACHE{$homedir} || ( $HOMEDIR_OK_CACHE{$homedir} = -e $homedir ? 1 : 0 ) ) {

        # homedir ok
    }
    else {
        Cpanel::Logger::cplog( "HOMEDIR: $homedir", 'info', __PACKAGE__, 1 );
        _handle_error( locale()->maketext('The current user does not have a home directory on the system.'), $opts );
        return;
    }

    my ( $emaildir, $emaildeliverdir );

    if ( $account =~ $Cpanel::Regex::regex{'commercialat'} ) {
        my ( $user, $domain ) = split /\@/, $account;
        $emaildir        = $homedir . '/etc/' . $domain . '/' . $user;
        $emaildeliverdir = $homedir . '/mail/' . $domain . '/' . $user;

        # Validate domain
        if ( !$no_checks && !-e $emaildir && !-e $homedir . '/etc/' . $domain ) {
            my $cpuser = $Cpanel::user;
            if ( !$cpuser ) {
                $cpuser = $Cpanel::user = ( Cpanel::PwCache::getpwuid($>) )[0];
            }
            if ( !-e '/var/cpanel/users/' . $cpuser ) {
                Cpanel::Logger::cplog( "Unable to resolve cPanel user for $account", 'warn', __PACKAGE__, 1 );
                _handle_error( locale()->maketext( 'Email directory for account “[_1]” does not exist.', $account ), $opts );
                return;
            }
        }
    }
    else {
        $emaildir        = $homedir . '/etc';
        $emaildeliverdir = $homedir . '/mail';
    }

    if ( $no_checks && $no_create ) {
        return wantarray
          ? ( $emaildir, $emaildeliverdir )
          : [ $emaildir, $emaildeliverdir ];
    }

    foreach my $dir ( $emaildir, $emaildeliverdir, $emaildir . '/.boxtrapper', $emaildir . '/.boxtrapper/forms' ) {
        if ( !-e $dir && !$no_create ) {
            if ( !Cpanel::SafeDir::MK::safemkdir( $dir, '0711' ) ) {
                $logger->info("Could not create dir \"$dir\": $!");
                _handle_error( locale()->maketext( 'Email directory for account “[_1]” does not exist.', $account ), $opts );
                return;
            }
        }
        if ( !-d $dir ) {
            Cpanel::Logger::cplog( "Missing directory $dir, BoxTrapper will not function properly", 'warn', __PACKAGE__, 1 );
            if ( $dir eq $homedir . '/mail' ) {
                Cpanel::Logger::cplog( "Mail directory $dir must be present for mail delivery!", 'warn', __PACKAGE__, 1 );
                _handle_error( locale()->maketext( 'Email directory for account “[_1]” does not exist.', $account ), $opts );
                return;
            }
        }
    }
    return wantarray ? ( $emaildir, $emaildeliverdir ) : [ $emaildir, $emaildeliverdir ];
}

sub BoxTrapper_getheader {
    my ( $header, $hdref, $whichone ) = @_;

    return if !_role_is_enabled();

    if   ($whichone) { $whichone--; }
    else             { $whichone = 0; }
    my @matching_headers = grep( m/^\Q$header\E:\s*/i, @{$hdref} );    #must be \s* not \s+
    return '' if !scalar @matching_headers;
    my $hresult = ( split( /:\s*/, $matching_headers[$whichone], 2 ) )[1];
    $hresult =~ s/\n\s+/ /g;                                           #convert multiline headers to a single line for processing
    $hresult =~ s/\r?\n$//;                                            #strip trailing line
    return $hresult // '';
}

sub _getheaders_from_fh {
    my $msg_fh = shift;
    my @headers;

    # Only slurp in the file contents if the file handle is a regular file. See Case 46270 before changing this logic.
    if ( ( stat($msg_fh) )[7] && fileno($msg_fh) > 2 ) {               # If we have a seekable file we can cheat a bit
        my $buffer_size = 8192;
        my $buffer;
        read( $msg_fh, $buffer, $buffer_size );

        #
        #  The headers are usually within the first 8192 bytes so we try to look there first as we can avoid quite a
        # few readlines if we find them there.  If not we look at the top and start again
        #
        if ( $buffer =~ m/\r?\n\r?\n/g && $+[0] ) {
            seek( $msg_fh, $+[0], 0 );
            foreach ( split( /(\r?\n)/, substr( $buffer, 0, $+[0] ) ) ) {
                if ( m/^\r?\n$/ || m/^\s+\S+/ ) {
                    $headers[$#headers] .= $_;
                }
                else {
                    push @headers, $_;
                }
            }
            pop @headers;    # get rid of separator \r?\n
        }
        else {

            # We did not find the headers, we need to reset to the top of the file
            seek( $msg_fh, 0, 0 );
        }
    }
    if ( !@headers ) {
        while ( readline($msg_fh) ) {
            if (m/^\s+\S+/) {
                $headers[$#headers] .= $_;
            }
            elsif (m/$Cpanel::Regex::regex{'emailheaderterminator'}/) {
                last;
            }
            else {
                push @headers, $_;
            }
        }
    }
    return \@headers;
}

sub BoxTrapper_getheaders {
    return if !_role_is_enabled();
    my $headers_ref = _getheaders_from_fh( \*STDIN );
    return wantarray ? @$headers_ref : $headers_ref;
}

sub BoxTrapper_getheadersfromfile {
    my ( $file, $opts ) = @_;
    $opts = {} if !$opts;

    return if !_role_is_enabled();

    if ( -e $file ) {
        if ( open( my $read_fh, '<', $file ) ) {
            my $headers_ref = _getheaders_from_fh($read_fh);
            close($read_fh);
            return wantarray ? @$headers_ref : $headers_ref;
        }
        else {
            my $error = $!;
            _handle_warn(
                locale()->maketext( 'The system failed to open the blocked mail message “[_1]” with the following error: [_2]', $file, $error ),
                "The system failed to open the blocked mail message $file with the following error: $error.",
                $opts,
            ) if $!;
        }
    }
    else {
        _handle_warn(
            locale()->maketext( 'The requested blocked mail message “[_1]” does not exist.', $file ),
            "The requested blocked mail message $file does not exist.",
            $opts,
        );
    }
    return wantarray ? () : [];
}

sub BoxTrapper_gethomedir {
    my $domain = shift;

    return if !_role_is_enabled();

    return $HOMEDIR_CACHE{$domain} if ( exists $HOMEDIR_CACHE{$domain} );

    BoxTrapper_initvars();

    if ( $> != $mailuser{'uid'} ) {
        return ( $HOMEDIR_CACHE{$domain} = ( Cpanel::PwCache::getpwuid($>) )[7] );
    }
    else {
        return ( $HOMEDIR_CACHE{$domain} = $mailuser{'dir'} );
    }

    Cpanel::Logger::cplog( "Unable to determine home directory for domain $domain", 'warn', __PACKAGE__, 1 );
    return;
}

sub BoxTrapper_getmailuser {
    return if !_role_is_enabled();
    my ( $muid, $mname, $mdir ) = ( Cpanel::PwCache::getpwnam('mailnull') )[ 0, 2, 7 ];
    if ( !$muid ) {
        ( $muid, $mname, $mdir ) = ( Cpanel::PwCache::getpwnam('mail') )[ 0, 2, 7 ];
    }
    if ( !$muid ) {
        Cpanel::Logger::cplog( 'Cannot determine mail user uid, please create mail user', 'die', __PACKAGE__ );
        return;    # Just in case ?
    }
    return wantarray ? ( 'uid' => $muid, 'name' => $mname, 'dir' => $mdir ) : $mname;
}

sub BoxTrapper_getourid {
    my $emaildir = shift;

    return if !_role_is_enabled();

    return if _is_demo();

    $emaildir =~ s/$Cpanel::Regex::regex{doubledot}//g;
    my $id;
    if ( -e $emaildir . '/.boxtrapper/id' ) {
        open( ID, '<', $emaildir . '/.boxtrapper/id' );
        chomp( $id = <ID> );
        close(ID);
    }

    if ( !$id || $id eq '' ) {
        $id = BoxTrapper_getranddata(32);
        open( ID, '>', $emaildir . '/.boxtrapper/id' );
        print ID $id;
        close(ID);
    }
    return $id;
}

sub _generate_msgid {
    my $timestr = '-' . time();

    # Store the mtime in the file name to avoid the problem in case 47038
    return BoxTrapper_getranddata( 32 - length($timestr) ) . $timestr;
}

sub BoxTrapper_getqueueid {
    my $dir = shift;

    return if !_role_is_enabled();

    my $queuedir = $dir . '/boxtrapper/queue/';
    my $rndfile  = _generate_msgid();
    alarm(50);
    while ( -e $queuedir . '/' . $rndfile . '.msg' ) {
        $rndfile = _generate_msgid();
    }
    alarm(0);
    return $rndfile . '.msg';
}

sub BoxTrapper_getsender {
    my $hdref = shift;

    return if !_role_is_enabled();

    return BoxTrapper_extractaddress( BoxTrapper_getheader( 'from', $hdref ) );
}

# This misspelling has to stay, alas.
sub BoxTrapper_getrecievedfrom {
    my $header = shift;

    return if !_role_is_enabled();

    $header =~ $Cpanel::Regex::regex{'getreceivedfrom'};
    return $1;
}

sub BoxTrapper_gettransportmethod {
    my $header = shift;

    return if !_role_is_enabled();

    $header =~ $Cpanel::Regex::regex{'getemailtransport'};
    return $1;
}

sub BoxTrapper_getwebdomain {
    my $webdomain = shift;

    return if !_role_is_enabled();

    my @best_no_ssl_domain_prefixes = ( 'mail.', 'www.', '' );    # ASSUMPTION: Following the pattern from mail config data
                                                                  # which assumes that mail.<domain> maps to the same server
                                                                  # as <domain> does. This should always work with a cPanel
                                                                  # user's domain since we create the sub-domain 'mail' for
                                                                  # each cPanel user owned domain on the server.

    my $current_user = ( Cpanel::PwCache::getpwuid($>) )[0];
    my $cpuser_ref   = Cpanel::Config::LoadCpUserFile::load($current_user);
    if ( !defined $webdomain || $webdomain eq '' ) {
        if ($cpuser_ref) {
            $webdomain = $cpuser_ref->{'DOMAIN'};
        }
        else {
            return Cpanel::Hostname::gethostname();
        }
    }

    my %domains = map { $_ => 1 } ( $cpuser_ref ? ( $cpuser_ref->{'DOMAIN'}, @{ $cpuser_ref->{'DOMAINS'} } ) : () );
    foreach my $best_no_ssl_domain_prefix (@best_no_ssl_domain_prefixes) {
        my $test_domain = $best_no_ssl_domain_prefix . $webdomain;

        # If we can't load the cpuser file, assume that this is served by
        # Apache.  Also, "www." isn't listed explicitly in the cpuser file, so
        # look for the main domain.
        my $is_served_by_apache = !%domains || $domains{$test_domain} || ( $best_no_ssl_domain_prefix eq 'www.' && $domains{$webdomain} );
        if ( Cpanel::Domain::Local::domain_or_ip_is_on_local_server($test_domain) && $is_served_by_apache ) {
            return $test_domain;
        }
    }

    return $best_no_ssl_domain_prefixes[0] . $webdomain;
}

sub BoxTrapper_isfromself {
    my ( $email, $account, $froms ) = @_;

    return if !_role_is_enabled();

    foreach my $from ( $account, split( /\s*\,\s*/, $froms ) ) {
        return 1 if Cpanel::StringFunc::Case::ToLower($email) eq Cpanel::StringFunc::Case::ToLower($from);
    }
    return;
}

sub BoxTrapper_loadconf {
    my $emaildir = shift;
    my $account  = shift;

    return if !_role_is_enabled();

    my %CNF;
    Cpanel::Config::LoadConfig::loadConfig( $emaildir . '/boxtrapper.conf', \%CNF, '=' );
    $CNF{'stale-queue-time'} ||= 15;
    $CNF{'froms'}            ||= $account;
    $CNF{'froms'} =~ s/[\r\n\f]//g;
    if ( !exists $CNF{'min_spam_score_deliver'} ) { $CNF{'min_spam_score_deliver'} = -25; }
    if ( !exists $CNF{'whitelist_by_assoc'} )     { $CNF{'whitelist_by_assoc'}     = 1; }
    $CNF{'min_spam_score_deliver'} = int $CNF{'min_spam_score_deliver'};
    $CNF{'whitelist_by_assoc'}     = int $CNF{'whitelist_by_assoc'};
    return wantarray ? %CNF : \%CNF;
}

sub BoxTrapper_loadfwdlist {
    my $dir = shift;

    return if !_role_is_enabled();

    my %FWDS;
    Cpanel::Config::LoadConfig::loadConfig( $dir . '/.boxtrapper/forward-list.txt', \%FWDS, undef, undef, undef, 1 );
    return grep { !/^\s*$/ } keys %FWDS;
}

sub BoxTrapper_logmatch {
    my ( $dir, $list, $header, $match, $linenum ) = @_;

    return if !_role_is_enabled();

    BoxTrapper_clog( 3, $dir, "Email matches rule \"$header $match\" Line $linenum in ${list}list" );

    return;
}

sub BoxTrapper_loopprotect {
    my ( $from, $to, $emaildir ) = @_;

    return if !_role_is_enabled();

    return if _is_demo();

    my ( $ok, $respondcount ) = Cpanel::MailLoopProtect::create_delivery_event( $from, $to, 6 );
    if ( !$ok ) {
        BoxTrapper_clog( 2, $emaildir, "Exiting for loop protection ($from) respondcount=$respondcount" );
        exit 0;
    }

    return;
}

sub BoxTrapper_nicedate {
    my ( $sec, $min, $hour, $mday, $mon, $year ) = ( localtime(shift) )[ 0, 1, 2, 3, 4, 5 ];
    return ( sprintf( '%02d', ++$mon ), sprintf( '%02d', $mday ), $year += 1900, sprintf( '%02d', $hour ), sprintf( '%02d', $min ), sprintf( '%02d', $sec ) );
}

sub BoxTrapper_removefromsearchdb {
    my ( $dir, $msgidlist ) = @_;

    return if !_role_is_enabled();

    return if _is_demo();

    if ( !-d $dir ) {
        $logger->info("Unable to proceed further in BoxTrapper_removefromsearchdb: Dir \"$dir\" does not exist. ");
        return;
    }

    my $search_db_fh = IO::Handle->new();

    # Make sure that the 'boxtrapper' dir exists prior to using it with the $sdb_file below.
    my $boxtrapper_dir = $dir . '/boxtrapper';
    if ( !-d $boxtrapper_dir ) {
        $logger->info("Dir \"$boxtrapper_dir\" did not exist for processing in BoxTrapper_removefromsearchdb ... Creating expected dir. ");
        if ( !Cpanel::SafeDir::MK::safemkdir( $boxtrapper_dir, '0700' ) ) {
            $logger->info("Could not create dir \"$boxtrapper_dir\": $!");
            return;
        }
    }

    my $sdb_file = $dir . '/boxtrapper/search.db';
    my ( $sdb_temp_file, $search_db_temp_fh ) = Cpanel::Rand::get_tmp_file_by_name($sdb_file);    # audit case 46806 ok

    if ( !-e $sdb_file ) {
        open( $search_db_fh, '>>', $sdb_file );
        close($search_db_fh);
    }

    my $sdblock = Cpanel::SafeFile::safeopen( $search_db_fh, '+<', $sdb_file );
    if ( !$sdblock ) {
        $logger->warn("Could not edit $sdb_file");
        return;
    }
    my @MSGS = (
        ref $msgidlist eq 'ARRAY'
        ? map { Cpanel::StringFunc::Trim::endtrim( $_, '.msg' ) } @{$msgidlist}
        : Cpanel::StringFunc::Trim::endtrim( $msgidlist, '.msg' )
    );
    my $line_remove_regex = quotemeta('<id>') . '(?:' . join( '|', @MSGS ) . ')' . quotemeta('</id>');
    while ( readline($search_db_fh) ) {
        if ( !/$line_remove_regex/o ) {
            syswrite( $search_db_temp_fh, $_ );
        }
    }

    unlink($sdb_file);
    link( $sdb_temp_file, $sdb_file );

    Cpanel::SafeFile::safeclose( $search_db_fh, $sdblock );
    unlink($sdb_temp_file);

    return;
}

sub BoxTrapper_updatesearchdb {
    my ( $dir, $msgid, $headers ) = @_;

    return if !_role_is_enabled();

    return if _is_demo();

    my $from    = BoxTrapper_getheader( 'from',    $headers );
    my $subject = BoxTrapper_getheader( 'subject', $headers );
    $subject =~ s/[\r\n]//g;
    $from    =~ s/[\r\n]//g;
    $msgid = Cpanel::StringFunc::Trim::endtrim( $msgid, '.msg' );

    if ( !-e $dir . '/boxtrapper/search.db' ) {
        BoxTrapper_rebuildsearchdb($dir);
        return;
    }

    my $sdblock = Cpanel::SafeFile::safeopen( \*SDB, '>>', $dir . '/boxtrapper/search.db' );
    if ( !$sdblock ) {
        $logger->warn("Could not write to $dir/boxtrapper/search.db");
        return;
    }
    my $sdb;
    $sdb->{$msgid}->{'from'}    = [$from];
    $sdb->{$msgid}->{'subject'} = [$subject];
    _writesearchdb( $sdb, \*SDB, 1 );
    Cpanel::SafeFile::safeclose( \*SDB, $sdblock );

    return;
}

sub BoxTrapper_rebuildsearchdb {
    my ($emaildir) = @_;

    return if !_role_is_enabled();

    return if _is_demo();

    my $sdb;
    opendir( QDIR, $emaildir . '/boxtrapper/queue' );
    while ( my $queuefile = readdir(QDIR) ) {
        next if ( $queuefile =~ /^\./ || $queuefile =~ /\.lock$/ );
        my $msgid   = Cpanel::StringFunc::Trim::endtrim( $queuefile, '.msg' );
        my $headers = BoxTrapper_getheadersfromfile( $emaildir . '/boxtrapper/queue/' . $queuefile );
        my $from    = BoxTrapper_getheader( 'from',    $headers );
        my $subject = BoxTrapper_getheader( 'subject', $headers );
        $subject =~ s/[\r\n]//g;
        $from    =~ s/[\r\n]//g;

        $sdb->{$msgid}->{'from'}    = [$from];
        $sdb->{$msgid}->{'subject'} = [$subject];
    }
    closedir(QDIR);

    my $sdblock = Cpanel::SafeFile::safeopen( \*SDB, '>', $emaildir . '/boxtrapper/search.db' );
    if ( !$sdblock ) {
        $logger->warn("Could not write to $emaildir/boxtrapper/search.db");
        return;
    }
    _writesearchdb( $sdb, \*SDB, 1 );
    Cpanel::SafeFile::safeclose( \*SDB, $sdblock );

    return;
}

sub BoxTrapper_queuemessage {
    my ( $dir, $email, $msgid ) = @_;

    return if !_role_is_enabled();

    return if _is_demo();

    $email =~ s/$Cpanel::Regex::regex{multipledot}/$Cpanel::Regex::regex{singledot}/g;
    $email =~ s/$Cpanel::Regex::regex{forwardslash}//g;
    $msgid = Cpanel::StringFunc::Trim::endtrim( $msgid, '.msg' );

    my $mbox_fh;
    my $mboxlock;
    eval {
        $mboxlock = Cpanel::SafeFile::safeopen( $mbox_fh, '>>', $dir . '/boxtrapper/verifications/' . $email ) || die "couldn't get lock: $!\n";
        print {$mbox_fh} $msgid . "\n" or die "couldn't print: $!\n";
        close $mbox_fh                 or die "couldn't flush data to disk: $!\n";
    };
    my $err = $@;
    Cpanel::SafeFile::safeclose( $mbox_fh, $mboxlock ) if $mbox_fh and $mboxlock;
    if ($err) {
        $logger->warn("Could not write to $dir/boxtrapper/verifications/$email: $err");
    }

    return;
}

sub BoxTrapper_sendformmessage {    ## no critic(ProhibitManyArgs)
    my ( $message, $emaildir, $email, $subject, $msgid, $rheaders, $webdomain, $acct, $id, $returnaddy, $rconf ) = @_;

    return if !_role_is_enabled();

    return if _is_demo();

    $emaildir =~ s/$Cpanel::Regex::regex{'doubledot'}//g;
    $message  =~ s/$Cpanel::Regex::regex{'doubledot'}//g;
    $msgid = Cpanel::StringFunc::Trim::endtrim( $msgid, '.msg' );

    my $msg_txt = _generate_formmessage( $message, $emaildir, $email, $subject, $msgid, $rheaders, $webdomain, $acct, $id, $returnaddy, $rconf );
    if ( my $pid = open( my $sendmail_fh, '|-' ) ) {
        print {$sendmail_fh} $msg_txt;
        close($sendmail_fh);
    }
    elsif ( $pid == 0 ) {
        exec( '/usr/sbin/sendmail', '-t', '-i', '-f', $acct ) or exit 1;
    }
    else {
        $logger->panic("fork() failed");
    }
    return;
}

sub _generate_formmessage {    ## no critic(ProhibitManyArgs)
    my ( $message, $emaildir, $email, $subject, $msgid, $rheaders, $webdomain, $acct, $id, $returnaddy, $rconf ) = @_;

    return if !_role_is_enabled();

    my $msg_txt;
    $msg_txt .= "Mime-Version: 1.0\n";
    $msg_txt .= "Content-Type: text/plain\n";
    my $headers = join( '', @{$rheaders} );
    open( my $form_letter_fh, '<', ( -e $emaildir . '/.boxtrapper/forms/' . $message . '.txt' ? $emaildir . '/.boxtrapper/forms/' . $message . '.txt' : '/usr/local/cpanel/etc/boxtrapper/forms/' . $message . '.txt' ) );
    $msg_txt .= "X-Boxtrapper: $id\n" . "X-Autorespond: $id\n" . "Precedence: auto_reply\n" . "X-Precedence: auto_reply\n";
    my $fromname;

    if ( $rconf->{'fromname'} && $rconf->{'fromname'} ne '' ) {
        $fromname = $rconf->{'fromname'};
        $msg_txt .= "From: \"" . $rconf->{'fromname'} . "\" <$returnaddy>\n";
    }
    else {
        $fromname = $returnaddy;
        $msg_txt .= "From: $returnaddy\n";
    }

    my $on = 1;

    my $orig_subj_encoded = $subject;
    Cpanel::Encoder::utf8::encode($orig_subj_encoded) if Cpanel::Encoder::utf8::is_utf8($orig_subj_encoded);

    while (<$form_letter_fh>) {
        if (tr/%//) {
            s/%acct%/$acct/g;
            s/%msgid%/$msgid/g;
            s/%subject%/$orig_subj_encoded/g;
            s/%email%/$email/g;
            s/%headers%/$headers/g;
            s/%fromname%/$fromname/g;
            s/%webdomain%/$webdomain/g;
            if ( /[^\000-\177]/ and my ($form_subj) = m/^Subject: (.+)$/ ) {
                my $verify_num = '';
                if ( $form_subj =~ s/(verify#.+)$// ) {
                    $verify_num = ' ' . $1;
                }

                # Use Base64 because the version of quoted-printable encoding used by MIME::QuotedPrint
                # is not convenient for encoding underscores and spaces. Leave the verification string
                # (which is plain ASCII) unencoded if it can be identified.
                Cpanel::Encoder::utf8::encode($form_subj) if Cpanel::Encoder::utf8::is_utf8($form_subj);
                $_ = "Subject: " . join( "\n ", map { "=?utf-8?B?$_?=" } split /\012/, MIME::Base64::encode_base64( $form_subj, "\012" ) ) . "\n" . $verify_num . "\n";
            }
            if (s/%if\s+([^\%]+)%//g) {
                my $cond = $1;
                if ( $cond eq 'can_verify_web' && !_suexec_status() ) {
                    $on = 0;
                }
            }
            if (s/%endif%//g) {
                $on = 1;
            }
        }
        $msg_txt .= $_ if $on;
    }
    close($form_letter_fh);
    return $msg_txt;
}

sub _suexec_status {
    return $suexec if defined $suexec;
    return Cpanel::Config::Httpd::Perms::webserver_runs_as_user( itk => 1, ruid2 => 1, suexec => 1 );
}

sub BoxTrapper_splitaddresses {
    my $addresses = shift;
    return if !length $addresses;

    return if !_role_is_enabled();

    $addresses =~ s/$Cpanel::Regex::regex{allspacetabchars}//g;
    return split( /[\;\,]+/, $addresses );
}

sub _writesearchdb {
    my ( $db, $fh, $encode ) = @_;
    foreach my $entry ( keys %{$db} ) {
        print {$fh} "<msg><id>$entry</id>";
        foreach my $key ( keys %{ $db->{$entry} } ) {
            print {$fh} map { "<$key>" . ( $encode ? Cpanel::Encoder::Tiny::safe_html_encode_str($_) : $_ ) . "</$key>" } @{ $db->{$entry}->{$key} };
        }
        print {$fh} "</msg>\n";
    }

    return;
}

sub is_authenticated_transport {
    my $transportmethod = shift;

    return if !_role_is_enabled();

    return 1 if ( $transportmethod eq 'asmtp'
        || $transportmethod eq 'esmtpa'
        || $transportmethod eq 'esmtpsa' );
    return 0;
}

sub is_local_trusted {
    return -e '/var/cpanel/feature_toggles/boxtrapper-dont-trust-local' ? 0 : 1;
}

sub is_trusted_transport {
    my $transportmethod = shift;

    return if !_role_is_enabled();

    return 1 if ( ( $transportmethod =~ m/local/ || $transportmethod eq 'trusted_mailprovider' || is_authenticated_transport($transportmethod) )
        && is_local_trusted() );
    return 0;
}

sub verified_messageid {
    my ( $account, $emaildir, $emaildeliverdir, $msgid ) = @_;

    return if !_role_is_enabled();

    $msgid =~ s/\///g;
    my @msgids = ($msgid);

    # Deliver all messages from sender
    my @headers    = BoxTrapper_getheadersfromfile( $emaildir . '/boxtrapper/queue/' . $msgid . '.msg' );
    my $whiteemail = BoxTrapper_extractaddress( BoxTrapper_getheader( 'from', \@headers ) );
    BoxTrapper_clog( 3, $emaildir, "Auto-Whitelisting $whiteemail" );
    BoxTrapper_addaddytolist( 'white', $whiteemail, $emaildir );
    if ( -e $emaildir . '/boxtrapper/verifications/' . $whiteemail ) {
        open my $verification_fh, '<', $emaildir . '/boxtrapper/verifications/' . $whiteemail;
        while ( readline($verification_fh) ) {
            chomp;
            next if (/^\s*$/);
            my $vmsgid = $_;
            $vmsgid =~ s/[\s\r\n\t]*//g;
            if ( -e $emaildir . '/boxtrapper/queue/' . $vmsgid . '.msg' ) {
                if ( $msgid ne $vmsgid ) { push( @msgids, $vmsgid ); }
            }
        }
        close $verification_fh;
    }
    foreach my $vmsgid (@msgids) {
        my ( $rvheaders, $bodyfh ) = BoxTrapper_extract_headers_return_bodyglobref( $emaildir . '/boxtrapper/queue/' . $vmsgid . '.msg' );
        my $vsubject = BoxTrapper_getheader( 'subject', $rvheaders );
        push @{$rvheaders}, "X-BoxTrapper-Queue: released via email verify\n";
        BoxTrapper_clog( 3, $emaildir, "Releasing queue for ${whiteemail}/${vsubject}" );
        BoxTrapper_delivermessage( $account, 1, $emaildir, $emaildeliverdir, $rvheaders, $bodyfh ) or warn "Unable to deliver messages due to I/O error" and return;
        unlink( $emaildir . '/boxtrapper/queue/' . $vmsgid . '.msg' );
    }
    BoxTrapper_removefromsearchdb( $emaildir, \@msgids );
    unlink( $emaildir . '/boxtrapper/verifications/' . $whiteemail );

    return;
}

sub _get_addresses_for_account {
    my ( $emaildir, $account ) = @_;

    return if !_role_is_enabled();

    my $conf  = BoxTrapper_loadconf( $emaildir, $account );
    my %known = map { $_ => 1 } Cpanel::BoxTrapper::CORE::BoxTrapper_extractaddresses( $conf->{'froms'} );
    $known{$account} = 1;
    if ( $account !~ tr{@}{} ) {
        $known{ $account . '@' . Cpanel::Hostname::gethostname() } = 1;
    }
    return \%known;
}

sub _is_demo {
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        my $locale = Cpanel::Locale->get_handle();
        my $error  = $locale->maketext('This feature is disabled in demo mode.');
        $Cpanel::CPERROR{'boxtrapper'} = $error;
        return 1;
    }
    return;
}

1;
