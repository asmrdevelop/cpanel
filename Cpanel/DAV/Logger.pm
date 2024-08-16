package Cpanel::DAV::Logger;

# cpanel - Cpanel/DAV/Logger.pm                    Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
use cPstrict;

use Cpanel::Umask ();

use Exporter qw{import};
our @EXPORT_OK = qw{logfunc dbg iolog};

use constant TOUCHFILE => '/.caldav/.debug';
use constant IO_LOG    => '/logs/DAV-io.log';
use constant DEBUG_LOG => '/logs/DAV-debug.log';
use constant FN_MARK   => "❱❱❱";

# I'm using package vars to make it easier to toggle in code.
our $debug = 0;
our $debug_log_path;
our $io_log_path;

=head1 NAME

Cpanel::DAV::Logger

=head1 DESCRIPTION

Logging for the CalDAV/CardDAV functionality in cpdavd.

=cut

################################################################################

# Since there is soooo much detailed logging output,
# it really helps to be able to find what you are looking for visually,
# so I'm using this for the time being.
# the basic 16 colors
my $reset_color    = "\e[0m";     # Resets back to what it was before
my $black          = "\e[30m";    # Black
my $red            = "\e[31m";    # Red
my $green          = "\e[32m";    # Green
my $yellow         = "\e[33m";    # Yellow
my $blue           = "\e[34m";    # Blue
my $magenta        = "\e[35m";    # Magenta
my $cyan           = "\e[36m";    # Cyan
my $white          = "\e[37m";    # White
my $gray           = "\e[90m";    # Gray
my $bright_red     = "\e[91m";    # Bright Red
my $bright_green   = "\e[92m";    # Bright Green
my $bright_yellow  = "\e[93m";    # Bright Yellow
my $bright_blue    = "\e[94m";    # Bright Blue
my $bright_magenta = "\e[95m";    # Bright Magenta
my $bright_cyan    = "\e[96m";    # Bright Cyan
my $bright_white   = "\e[97m";    # Bright White

# some from the 256 color spectrum
my $hot_pink      = "\e[38;5;200m";
my $pastel_pink   = "\e[38;5;219m";
my $pastel_blue   = "\e[38;5;69m";
my $pastel_green  = "\e[38;5;122m";
my $pastel_red    = "\e[38;5;125m";
my $pastel_brown  = "\e[38;5;137m";
my $pastel_orange = "\e[38;5;172m";
my $log_tan       = "\e[38;5;137m";
my $log_blue      = "\e[38;5;189m";
my $log_red       = "\e[38;5;95m";
my $log_green     = "\e[38;5;23m";
my $log_dark      = "\e[38;5;245m";
my $props_color   = "\e[38;5;75m";
my $props_color2  = "\e[38;5;87m";
my $path_color    = "\e[38;5;223m";
my $funcs_color   = "\e[38;5;202m";
my $ns_color      = "\e[38;5;25m";

################################################################################

=head1 FUNCTIONS

=head2 maybe_set_debug($homedir)

Check if we want debug output or not. This is determined by the presence/absence of
the ~/.caldav/.debug touch file in a cPanel user's homedir ($homedir).

=cut

sub maybe_set_debug ($homedir) {
    $debug = 0;
    if ( $homedir && -e $homedir . TOUCHFILE() ) {
        $debug          = 1;
        $debug_log_path = $homedir . DEBUG_LOG();
        $io_log_path    = $homedir . IO_LOG();
        require Data::Dumper;
        require Cpanel::FileUtils::Touch;
        no warnings qw{once};    # Irritating, but necessary for the following
        $Data::Dumper::Indent   = 1;
        $Data::Dumper::Sortkeys = 1;

        # Create the log file here so that we don't have to run a stat later
        # and try to chmod it.
        # This data is more sensitive than the regular ~/logs/DAV-error.log,
        # so we take an additional step to help enforce limited access to it
        foreach my $logfile ( $homedir . DEBUG_LOG(), $homedir . IO_LOG() ) {
            my $umask = Cpanel::Umask->new(0077);
            Cpanel::FileUtils::Touch::touch_if_not_exists($logfile);
        }

    }
    return $debug;
}

=head2 iolog(@lines)

iolog is intended as a log of just requests data and return values,
not all the extra stuff in the general debug log.

The lines are written to ~/logs/DAV-io.log

=cut

sub iolog (@lines) {
    return _dbg_print( $io_log_path, @lines );
}

=head2 logfunc($sub_line)

Rather than use a function wrapper to do this semi-dynamically, we can use this to in each function to automatically register useful information

=cut

sub logfunc ( $sub_line = 2 ) {

    # no need to clutter the logs with ourself, but leave it available for remote callers
    my $c_func      = ( caller(1) )[3] =~ s/Cpanel::DAV:://r;
    my @caller_self = caller(0);
    my $self_file   = $caller_self[1];

    # just put logfunc() as the 2nd line of every sub to keep accurate, or pass it
    my $self_line = $caller_self[2] - $sub_line;
    $self_file =~ s/^\/usr\/local\/cpanel\///;
    return dbg( FN_MARK() . " :[$c_func]: at $self_file : $self_line" );
}

=head2 dbg(@args)

Skipped if debug logging is not enabled: Given one or more pieces of text or structured data (in @args),
format and log this to ~/logs/DAV-debug.log.

=cut

sub dbg (@args) {
    return _dbg_print( $debug_log_path, @args );
}

sub _dbg_print ( $logfile, @args ) {
    return if !$debug || !$logfile || !@args;

    my ( $pkg, $file, $line, $sub, $hasargs ) = caller(1);

    if ( index( $args[0], FN_MARK() ) == 0 ) {

        # this is from logfunc(), so we want to find the caller before that
        ( $pkg, $file, $line, $sub, $hasargs ) = caller(3);
        $file //= '(no file)';
        $line //= '(no line number)';
        $file =~ s/^\/usr\/local\/cpanel\///;
    }
    $file =~ s/^\/usr\/local\/cpanel\///;

    my $out           = '[' . $$ . '] [' . scalar( localtime( time() ) ) . "] [$file : $line] ";
    my $needs_newline = 0;
    foreach my $what (@args) {
        my $ref = _get_ref_type($what);
        if ($ref) {
            next if !grep { $ref && $ref eq $_ } qw{HASH ARRAY};
            if ( $ref eq 'HASH' ) {

                # Shallow copy the hash ref so we don't alter the values for the caller
                my $what_copy = { %{$what} };

                # delete auth data from known places, while leaving a placeholder so debuggers know it was actually present
                # Be very careful in what you send to the dbg logger; anything that will contain passwords needs to be redacted here.
                # Currently this is all in hashes (this block), but similar will need to be done for arrays / strings / etc if you pass sensitive data in those var types
                if ( defined $what_copy->{'smtp_user'} )                                                     { $what_copy->{'smtp_user'}                 = 'REDACTED'; }    # from %self
                if ( defined $what_copy->{'smtp_pass'} )                                                     { $what_copy->{'smtp_pass'}                 = 'REDACTED'; }    # from %self
                if ( defined $what_copy->{'authorization'} )                                                 { $what_copy->{'authorization'}             = 'REDACTED'; }    # from $request->headers directly
                if ( defined $what_copy->{'_headers'} && defined $what_copy->{'_headers'}{'authorization'} ) { $what_copy->{'_headers'}{'authorization'} = 'REDACTED'; }    # from headers as a whole $request object. check defined on both to prevent autovivifying _headers
                $out .= "\n(ref=$ref)$log_tan" . Data::Dumper::Dumper($what_copy) . "$reset_color";
            }
            else {
                $out .= "\n(ref=$ref)$log_tan" . Data::Dumper::Dumper($what) . "$reset_color";
            }
        }
        else {
            # It's probably just a regular text string..

            # TODO - this still shows the ANSI escape sequences in vi, nano, less, and some other common tools
            #        used to look at log files, so while this is great for tail, more, cat and others, there needs
            #        to be an option to disable it, and instead convert all the weird little braces to just [$thing] or
            #        whatever, no colors.
            #      - we could consider using unicode chars in some way, but the effect is not as clear when trying to visually
            #        locate and isolate what you are looking for.
            #        $what =~ s/(\_\[([^\]]+)\]\_)/🟦$2🟦/g;
            #      - another bad idea would be to output to different log files, one with color and one without. But that's pretty nutty.
            #
            # We can also just suggest anyone wanting to use a tool that doesn't like ansi color escapes in it to just pipe it through sed ?
            # cat /tmp/cpdavd.log | sed $'s/\e\\[[0-9;:]*[a-zA-Z]//g' > myboring.log
            #
            # `less` can still show colors if you use `less -R` for raw mode
            # You can also pipe less to `ccze -A` (if installed) for colorification
            #
            # To use coloring, wrap the text you want colored with something like -[colored text goes here]-
            next if !length $what;
            $what =~ s/(\_\[([^\]]+)\]\_)/${props_color}$2${reset_color}/g;      # function / sub routine names
            $what =~ s/(\-\[([^\]]+)\]\-)/${props_color2}$2${reset_color}/g;     # properties related
            $what =~ s/(\(\[([^\]]+)\]\))/${path_color}$2${reset_color}/g;       # Paths
            $what =~ s/(\{\[([^\]]+)\]\})/${log_tan}$2${reset_color}/g;          # parsing functions (currently just _parse_request_payload)
            $what =~ s/(\~\[([^\]]+)\]\~)/${cyan}$2${reset_color}/g;             # _request_wrapper
            $what =~ s/(\=\[([^\]]+)\]\=)/${log_green}$2${reset_color}/g;        # sharing/ACLs/metadata
            $what =~ s/(\:\[([^\]]+)\]\:)/${funcs_color}$2${reset_color}/g;      # calling function
            $what =~ s/(\#\[([^\]]+)\]\#)/${log_dark}$2${reset_color}/g;         # raw text of processed properies
            $what =~ s/(\/\[([^\]]+)\]\/)/${ns_color}$2${reset_color}/g;         # namespace for property
            $what =~ s/(\*\[([^\]]+)\]\*)/${pastel_pink}$2${reset_color}/g;      # request payload
            $what =~ s/(\+\[([^\]]+)\]\+)/${bright_yellow}$2${reset_color}/g;    # request tags
            $what =~ s/(\!\[([^\]]+)\]\!)/${bright_red}$2${reset_color}/g;       # important errors
            $out .= $what;
            $needs_newline++;
        }
    }
    $out .= "\n" if $needs_newline;

    my $opened = open( my $dbg_fh, '>>', $logfile );
    unless ($opened) {
        warn "Can't open $logfile for writing: $!";
        return;
    }
    print $dbg_fh $out;
    return;
}

sub _get_ref_type ($ref) {
    my $rtype = ref $ref || '';
    $rtype = 'HASH' if UNIVERSAL::isa( $ref, 'HASH' );    # Technically true...
    return uc($rtype);
}

1;
