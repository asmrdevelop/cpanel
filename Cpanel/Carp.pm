package Cpanel::Carp;

# cpanel - Cpanel/Carp.pm                          Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Parser::Vars ();

our ( $SHOW_TRACE, $OUTPUT_FORMAT, $VERBOSE ) = ( 1, 'text', 0 );

my $__CALLBACK_AFTER_DIE_SPEW;    # Set when we need to run a code ref after spewing on die

my $error_count = 0;

sub import { return enable(); }

sub enable {
    my (
        $callback_before_warn_or_die_spew,    # Runs before the spew on warn or die, currently used in cpanel to ensure we emit headers before body in the event of a warn or die spew
        $callback_before_die_spew,            # Runs before the spew on die, not currently used
        $callback_after_die_spew,             # Runs after the spew on die, currently used in whostmgr to ensure we emit the javascript footer when we die to avoid the UI breaking
    ) = @_;

    $SIG{'__WARN__'} = sub {                  ## no critic qw(Variables::RequireLocalizedPunctuationVars)
        my @caller = caller(1);
        return if defined $caller[3] && index( $caller[3], 'eval' ) > -1;    # Case 35335: Quiet spurious warn errors from evals
                                                                             # Note: $^S really can't be used here because most of
                                                                             # cPanel's code will is wrapped in eval {} so we only
                                                                             # want to block the warning if the previous caller was eval {}

        ++$error_count;

        ## Generate Cpanel::Time::localtime2timestamp format timestamp
        my $time = time();
        my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime($time);

        # Generate a timezone string without calling POSIX::strftime.
        my ( $gmmin, $gmhour, $gmday ) = ( gmtime($time) )[ 1, 2, 3 ];

        # Unfortunately, the offset isn't as trivial as we would hope.
        #  - Not all timezones are offset by integral hours (need minutes to offset correctly)
        #  - The simple subtraction went nuts near midnight, because GMT and local time are
        #    on different days. The last term moves by number of minutes in a day in that case.
        my $gmoffset        = ( $hour * 60 + $min ) - ( $gmhour * 60 + $gmmin ) + 1440 * ( $mday <=> $gmday );
        my $tz              = sprintf( '%+03d%02d', int( $gmoffset / 60 ), $gmoffset % 60 );
        my $error_timestamp = sprintf( '%04d-%02d-%02d %02d:%02d:%02d %s', $year + 1900, $mon + 1, $mday, $hour, $min, $sec, $tz );

        my $longmess;
        my $ignorable;
        if ( UNIVERSAL::isa( $_[0], 'Cpanel::Exception' ) ) {
            $longmess = Cpanel::Carp::safe_longmess( $_[0]->to_locale_string() );
        }
        elsif ( ref $_[0] eq 'Template::Exception' ) {
            $longmess = Cpanel::Carp::safe_longmess( "Template::Exception:\n\t[TYPE]=[" . $_[0]->[0] . "]\n\t[INFO]=[" . $_[0]->[1] . "]\n\t[TEXT]=[" . ( ref $_[0]->[2] eq 'SCALAR' ? ${ $_[0]->[2] } : $_[0]->[2] ) . "]\n" );
        }
        else {
            $longmess  = Cpanel::Carp::safe_longmess(@_);
            $ignorable = 1 if index( $_[0], 'Use of uninitialized value' ) == 0;
        }

        my $error_container_text = 'A warning occurred while processing this directive.';

        # Always record longmess in error_log
        my $current_file = $Cpanel::Parser::Vars::file || 'unknown';
        print STDERR "[$error_timestamp] warn [Internal Warning while parsing $current_file $$] $longmess\n\n";

        ## the correct spelling is 'suppress'
        return if ( $OUTPUT_FORMAT eq 'suppress' || $OUTPUT_FORMAT eq 'supress' || $ENV{'CPANEL_PHPENGINE'} );

        # Do nothing.  The user doesn't want to see this.
        return if $ignorable && !$VERBOSE;

        _run_callback_without_die_handler($callback_before_warn_or_die_spew) if $callback_before_warn_or_die_spew;

        if ( $OUTPUT_FORMAT eq 'html' ) {
            if ($SHOW_TRACE) {
                _print_without_die_handler( _generate_html_error_message( 'warn', $error_container_text, $longmess ) );
            }
            else {
                _print_without_die_handler(qq{<span class="error" style="cursor:hand;cursor:pointer;">[$error_container_text]</span>});
            }
        }
        elsif ( $OUTPUT_FORMAT eq 'xml' ) {
            _print_without_die_handler("<error>$error_container_text</error>");
        }
        else {
            _print_without_die_handler("[$error_container_text]\n");
        }
    };

    $SIG{'__DIE__'} = sub {    ## no critic qw(Variables::RequireLocalizedPunctuationVars)

        # Case 35335: Quiet spurious die errors from evals
        return if $^S;

        # Just rethrow errors that occur during module loading.  We're almost
        # certainly in an eval, so we'll handle it later.  If we don't do this,
        # we get errors in the interface any time module loading fails, even
        # inside an eval.
        die $_[0] unless defined $^S;

        # after die is trapped the first time, it's likely that re-trapping a second, or Nth time, is "the wrong thing" #
        # this is because if there's further issues, such as out of memory, a de-reference on a now undefined scalar, #
        # the trap will keep triggering creating an infinite loop. it's better to just remove the handler on the first #
        # and allow the perl engine to simply spew or exit for all future die's #
        delete $SIG{'__DIE__'};
        _run_callback_without_die_handler($callback_before_warn_or_die_spew) if $callback_before_warn_or_die_spew;
        _run_callback_without_die_handler($callback_before_die_spew)         if $callback_before_die_spew;

        $__CALLBACK_AFTER_DIE_SPEW = $callback_after_die_spew;

        goto \&spew_on_die;
    };

    return 1;
}

sub spew_on_die {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my ($err) = @_;

    ++$error_count;

    ## Generate Cpanel::Time::localtime2timestamp format timestamp
    my $time = time();
    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime($time);

    # Generate a timezone string without calling POSIX::strftime.
    my ( $gmmin, $gmhour, $gmday ) = ( gmtime($time) )[ 1, 2, 3 ];

    # Unfortunately, the offset isn't as trivial as we would hope.
    #  - Not all timezones are offset by integral hours (need minutes to offset correctly)
    #  - The simple subtraction went nuts near midnight, because GMT and local time are
    #    on different days. The last term moves by number of minutes in a day in that case.
    my $gmoffset        = ( $hour * 60 + $min ) - ( $gmhour * 60 + $gmmin ) + 1440 * ( $mday <=> $gmday );
    my $tz              = sprintf( '%+03d%02d', int( $gmoffset / 60 ), $gmoffset % 60 );
    my $error_timestamp = sprintf( '%04d-%02d-%02d %02d:%02d:%02d %s', $year + 1900, $mon + 1, $mday, $hour, $min, $sec, $tz );

    my $error_text;
    if ( UNIVERSAL::isa( $err, 'Cpanel::Exception' ) ) {
        $error_text = Cpanel::Carp::safe_longmess( $err->to_locale_string() );
    }
    elsif ( UNIVERSAL::isa( $err, 'Template::Exception' ) ) {
        $error_text = Cpanel::Carp::safe_longmess( "Template::Exception:\n\t[TYPE]=[" . $err->type() . "]\n\t[INFO]=[" . $err->info() . "]\n\t[TEXT]=[" . $err->text() . "]\n" );
    }
    else {
        $error_text = Cpanel::Carp::safe_longmess(@_);
    }

    # Always record error in error_log
    my $current_file = $Cpanel::Parser::Vars::file || 'unknown';
    print STDERR "[$error_timestamp] die [Internal Death while parsing $current_file $$] $error_text\n\n";

    ## the correct spelling is 'suppress'
    return if ( $OUTPUT_FORMAT eq 'suppress' || $OUTPUT_FORMAT eq 'supress' || $ENV{'CPANEL_PHPENGINE'} );

    my $error_container_text = 'A fatal error or timeout occurred while processing this directive.';

    if ( $OUTPUT_FORMAT eq 'html' ) {
        if ($SHOW_TRACE) {
            _print_without_die_handler( _generate_html_error_message( 'error', $error_container_text, $error_text ) );
        }
        else {
            _print_without_die_handler(qq{<span class="error" style="cursor:hand;cursor:pointer;">[$error_container_text]</span>});
        }
    }
    elsif ( $OUTPUT_FORMAT eq 'xml' ) {
        _print_without_die_handler("<error>[$error_container_text]</error>");
    }
    else {
        _print_without_die_handler("[$error_container_text]\n");
    }

    _run_callback_without_die_handler($__CALLBACK_AFTER_DIE_SPEW) if $__CALLBACK_AFTER_DIE_SPEW;

    return;
}

my @SAFE_LONGMESS_KEY_REGEXP_ITEMS = (
    '(?<![a-zA-Z0-9_])pw(?![a-zA-Z0-9_])',
    qw(
      hash
      pass
      auth
      root
      key
      fullbackup
    ),
);

my @SAFE_LONGMESS_FUNCTION_REGEXP_ITEMS = (
    @SAFE_LONGMESS_KEY_REGEXP_ITEMS,
    '__ANON__',
);

#  _print_without_die_handler
#
#  If the print fails because the file handle or object
#  print would write to has been destoryed this could cause
#  a loop if it was called from inside the SIGDIE handler.
#
#  This function disables the die handler before attempting
#  to print.  Note errors should NOT be trapped here.
#
#  This can be called from inside a __WARN__ or __DIE__
#  SIG handler so we must reset them to defaults to ensure
#  this does not loop
#
#  Because we do a print in this code, it is possible to get
#  SIGPIPE, which some of our code turns into an exception.
#  Because our __DIE__ handler in this module does a goto(),
#  Perl’s usual behavior of disabling $SIG{__DIE__} during a
#  __DIE__ handler doesn’t happen, and we can get infinite recursion.
#
sub _print_without_die_handler {
    my ($text) = @_;

    local $SIG{'__WARN__'} = sub { };
    local $SIG{'__DIE__'}  = 'DEFAULT';

    return print $text;
}

# _run_callback_without_die_handler
# Just like _print_without_die_handler but for running
# a coderef.
#
sub _run_callback_without_die_handler {
    my ($callback) = @_;
    local $SIG{'__WARN__'} = sub { };
    local $SIG{'__DIE__'}  = 'DEFAULT';

    return $callback->();
}

sub _generate_html_error_message {
    my ( $type, $error_container_message, $error_message ) = @_;

    require Cpanel::Encoder::Tiny;
    my $safe_error_message = Cpanel::Encoder::Tiny::safe_html_encode_str($error_message);

    # This box looks pretty when cjt is loaded, however it will downgrade
    # gracefully if it is not

    return qq[
<style type="text/css">.cpanel_internal_message_container {display: inline-block; margin: 10px; width: auto;} .cpanel_internal_message { border: 1px solid #fff; outline-style: solid; outline-width: 1px; outline-color: #aaa; padding: 5px; } .cpanel_internal_error_warn { background-color: #FFF6CF; } .cpanel_internal_error_error { background-color: #F8E7E6; }</style>
<div id="cpanel_notice_item_$error_count" class="cjt-pagenotice-container cjt-notice-container cpanel_internal_message_container internal-error-container">
    <div class="yui-module cjt-notice cjt-pagenotice cjt-notice-$type">
        <div class="cpanel_internal_message cpanel_internal_error_$type bd">
            <div class="cjt-notice-content" style="width: 420px;">
                <span>
                    $error_container_message
                    <a
                        class="error"
                        style="cursor:hand;cursor:pointer;"
                        onClick="document.getElementById('cpanel_internal_error_$error_count').style.display='';this.style.display='none'; return false;">
                        [show]
                    </a>
                    <a
                        class="error"
                        style="cursor:hand;cursor:pointer;"
                        onClick="document.getElementById('cpanel_notice_item_$error_count').style.display='none'; return false;">
                        [close]
                    </a>
                </span>
                <div id="cpanel_internal_error_$error_count" style="display:none;">
                    <textarea class="cpanel_internal_error_$type" style="font-weight:900; height:200px; width:410px; color: black;">$safe_error_message</textarea>
                </div>
            </div>
        </div>
    </div>
</div>
    ];
}

sub safe_longmess {
    require Carp;
    $Carp::Internal{'Cpanel::Carp'} = 1;
    return sanitize_longmess( scalar Carp::longmess(@_) );
}

my ( $key_regexp, $key_regexp_double, $function_regexp );

sub sanitize_longmess {

    _build_regexes() if !$key_regexp;

    # DO NO ALLOW PLAIN TEXT PASSWORDS IN LOG FILE
    #
    # Note: this can be a tight loop.  If there are lots of users with quota
    # issues this can slow down ccs rebuilds so we only call _sanitize_line if
    # we are sure we need to modify it
    return join(
        "\n",
        map {
            # We check to see if a line needs to be sanitized if it has a quoted
            # string and it has one of the terms listed in $key_regexp (single quoted terms)
            # or in $key_regexp_double (double quoted items)
            #
            # Additionally we also look at items that are being shown
            # as passed to functions in the backtrace with $function_regexp
            #
            ( tr{'"}{} && ( m{$key_regexp}o || m{$key_regexp_double}o || ( ( $_ =~ m{^[ \t]*([^\(]+)\(} )[0] || '' ) =~ m{$function_regexp}o ) )    # matches a line that needs to be sanitized
              && _sanitize_line($_);                                                                                                                # sanitize
            $_
        } split( m{\n}, $_[0] )
    ) . "\n";
}

sub error_count {
    return $error_count;
}

sub _sanitize_line {    # Operates directly on $_[0] for speed
                        # We could get called in a loop if this fails to
                        # load so we need to local __DIE__ and __WARN__
    if ( !$INC{'Cpanel/Regex.pm'} ) {    # PPI NO PARSE - inc check
        local $@;
        eval {
            local $SIG{__DIE__};
            local $SIG{__WARN__};
            require Cpanel::Regex;    # PPI NO PARSE - inc check
        };
    }
    $_[0] =~ s/$Cpanel::Regex::regex{'singlequotedstring'}/__CPANEL_HIDDEN__/go if index( $_[0], q{'} ) != -1;
    $_[0] =~ s/$Cpanel::Regex::regex{'doublequotedstring'}/__CPANEL_HIDDEN__/go if index( $_[0], q{"} ) != -1;
    return 1;
}

sub _build_regexes {

    # See notes in case 100761
    # Due to perlcc 5.6 limitations, we have to declare the following
    # within a function. Declaring them has package variables, will
    # cause compile issues.
    my $key_regexp_items = join '|', @SAFE_LONGMESS_KEY_REGEXP_ITEMS;
    $key_regexp = qr<
        '
        .*?
        (?:
            $key_regexp_items
        )
        .*?
        '
        \s*
        ,
    >x;

    $key_regexp_double = $key_regexp;
    $key_regexp_double =~ tr{'}{"};    # "' fix for poor editors

    my $function_regexp_items = join '|', @SAFE_LONGMESS_FUNCTION_REGEXP_ITEMS;
    $function_regexp = qr<
        ::
        .*?
        (?:
            $function_regexp_items
        )
        .*?
        $
    >x;

    return 1;
}

1;
