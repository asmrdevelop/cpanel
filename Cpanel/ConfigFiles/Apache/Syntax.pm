package Cpanel::ConfigFiles::Apache::Syntax;

# cpanel - Cpanel/ConfigFiles/Apache/Syntax.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

######################################################################################################
#### This module is a modified version of EA3’s distiller’s code, it will be cleaned up via ZC-5317 ##
######################################################################################################

use strict;
use warnings;

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::ConfigFile::Apache::Syntax - Check the apache conf syntax

=cut

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Config::Httpd::EA4 ();
use Cpanel::FileUtils::Lines   ();

use Cpanel::Imports;

our $MAX_SYNTAX_CHECK_ATTEMPTS = 5;
our $READ_SIZE                 = 1 << 19;

=head2 check_syntax($file)

Returns a hash ref, with two items status and message.

    Failure:

    {
        'status' => 0,
        'message' => 'You forgot\nto dot your eyes.\nand cross your tees'
    }

    Success:

    {
        'status' => 1,
        'message' => 'Syntax OK'
    }

NOTE: In contrast to find_httpd_conf_errors, a success return from this
function means that the syntax checked out ok. No distinction is made
between "An error occurred while checking the syntax" and "the syntax
check succeeded, and the syntax is invalid."

=cut

sub check_syntax {
    my $file = shift || apache_paths_facade->file_conf();

    my $test_file   = $file;
    my $line_offset = 0;

    if ( Cpanel::Config::Httpd::EA4::is_ea4() && $file ne apache_paths_facade->file_conf() ) {

        # if the system is EA4 and the file is not httpd.conf, then we should
        # copy over the file to a new one with a new first line that includes the conf.modules.d directory
        ( $line_offset, $test_file ) = _create_test_file($file);
    }

    my $ref = _find_httpd_conf_errors($test_file);
    unlink $test_file if $test_file ne $file;

    if ( !$ref->{'status'} ) {
        return {
            'status'  => 0,
            'message' => $ref->{'message'},
        };
    }

    if ( $ref->{'status'} == 1 && length( $ref->{'message'} ) == 0 ) {
        return {
            'status'  => 1,
            'message' => 'Syntax OK',
        };
    }

    my $output;
    my @errors = split( /\n/, $ref->{'message'} );

    # if the caller wants an array, it wants this output.
    while ( scalar @errors ) {
        my $line = shift(@errors);
        next if !length $line;    # case CPANEL-10211: empty lines previously caused this to halt

        if ( $line =~ /\AAH00526: Syntax error on line (\d+) of ([^:]+):\s?(.?)\z/ ) {
            my $line      = $1;
            my $cfgfile   = $2;
            my $cfgreason = $3;

            $line = $line - $line_offset;
            $cfgfile   =~ s/\.cfgcheck$//;
            $cfgreason =~ s/:\s*$//;
            if ( !$cfgreason ) {
                $cfgreason = shift @errors;
                chomp $cfgreason;
            }

            my $cfginfo = Cpanel::FileUtils::Lines::get_file_lines( $cfgfile, $line );
            $output .= "Configuration problem detected on line $line of file $cfgfile";
            if ( $cfgreason =~ /invalid\s+command/ ) {
                $output .= "(do you need an IfModule statement? https://go.cpanel.net/customdirectives)";
            }
            $output .= ":\t$cfgreason\n\n";

            if ( exists $cfginfo->{'lines'} ) {
                $output .= "\t--- $cfgfile ---\n";
                foreach my $part ( 'previouslines', 'lines', 'afterlines' ) {
                    if ( $cfginfo->{$part} ) {
                        foreach my $opt ( @{ $cfginfo->{$part} } ) {
                            chomp( $opt->{'data'} );
                            $output .= "\t" . $opt->{'line'} . ( $part eq 'lines' ? ' ===> ' : '' ) . $opt->{'data'} . ( $part eq 'lines' ? ' <===' : '' ) . "\n";
                        }
                    }
                }
                $output .= "\t--- $cfgfile ---\n\n";
            }
        }
        else {
            $output .= $line . "\n";
        }
    }

    $output = join( '', "--- Syntax Not OK ---\n", @errors ) if !defined $output;

    return {
        'status'  => 0,
        'message' => $output,
    };
}

=head2 find_httpd_conf_errors($httpd_conf_text_sr)

Returns a hash ref, with two items status and message.

    Failure:

    {
        'status' => 0,
        'message' => 'You forgot\nto dot your eyes.\nand cross your tees'
    }

    Success:

    {
        'status' => 1,
        'message' => 'Syntax OK'
    }

NOTE: Success for this function just means that we checked httpd.conf.
It does *NOT* mean that httpd.conf is valid; for that, check \@errors.

e.g.:
my ( $ok, $errs ) = find_httpd_conf_errors( \$httpdconf_text );
die "Could not check httpd.conf validity: $errs" if !$ok;
die "httpd.conf is invalid:\n" . join("\n", @$errs ) if @$errs;

NOTE: The errors are returned as an array ref, NOT as a scalar!
This is because Apache can return multiple errors at the same time.
=cut

sub find_httpd_conf_errors {
    my ($httpd_conf_text_sr) = @_;

    require Cpanel::TempFile;
    my $tempfile_obj = Cpanel::TempFile->new();
    my ( $tfile, $tfh ) = $tempfile_obj->file();
    print {$tfh} $$httpd_conf_text_sr;
    close $tfh;

    return _find_httpd_conf_errors($tfile);
}

#The implementation function that takes a file path rather than a scalar ref.
sub _find_httpd_conf_errors {
    my ($file) = @_;

    if ( !-x apache_paths_facade->bin_httpd() ) {
        logger->warn('Unable to locate executable Apache binary');
        return {
            'status'  => 0,
            'message' => 'Syntax check failed. Unable to locate executable Apache binary',
        };
    }

    my $attempts = 0;
    my $run;
    #
    # If we get SIGTERM (usually chkservd) during the check_syntax
    # we will retry up to MAX_SYNTAX_CHECK_ATTEMPTS
    # This is important as it avoids a race condition that
    # prevents httpd from recovering from a broken httpd.conf
    #
    while ( ++$attempts <= $MAX_SYNTAX_CHECK_ATTEMPTS ) {
        $run = _run_apache_syntax_check($file);
        if ( $run->CHILD_ERROR() ) {
            my $exit_sig  = $run->signal_code();
            my $exit_code = $run->error_code();

            require Cpanel::Signal::Numbers;
            if ( $exit_sig == $Cpanel::Signal::Numbers::SIGNAL_NUMBER{'TERM'} ) {
                logger->warn("httpd got a SIGTERM during syntax check");
                sleep(1);
                next unless $attempts == $MAX_SYNTAX_CHECK_ATTEMPTS;    # retry -- got sig term
            }

            if ( $exit_sig || $run->dumped_core() || $exit_code > 1 ) {
                return 0 if !wantarray;
                my $combined_output = join( "\n", $run->stdout(), $run->stderr() );
                return {
                    'status'  => 0,
                    'message' => join( "\n", $run->autopsy(), 'Output was:', '---', $combined_output, '---' ),
                };
            }

            last;
        }
        else {
            last;
        }
    }

    my @errors;
    my $combined_output = join( "\n", $run->stdout(), $run->stderr() );
    substr( $combined_output, 0, 0, "\n" );

    if ( $combined_output !~ m{\n[ \t]*syntax\s+ok}si ) {
        push @errors, $run->autopsy();
        for my $line ( split( m{\n}, $combined_output ) ) {
            #
            # hide spurious wildcard warnings
            #
            if ( length $line && ( $line =~ m/(?:error|syntax)/i ) || ( $line !~ m/\[([^:]+:)?(?:info|notice|debug|warn)\]/ && $line !~ m/^[\t ]*Warning:/i && $line !~ m/NameVirtualHost address is not supported/i ) ) {
                push @errors, $line;
            }
        }
    }

    return {
        'status'  => 1,
        'message' => join( "\n", @errors ),
    };
}

sub _run_apache_syntax_check {
    require Cpanel::ApacheConf::Check;
    goto \&Cpanel::ApacheConf::Check::check_path;
}

# _create_test_file
#
# Create a file suitable for validation of apache configurations
# temporarily modified to have an extra line in it on an EA4 system (to include apache config)
#
# returns: ( $number_of_lines_added, $test_file )
sub _create_test_file {
    my ($source_file) = @_;

    my $number_of_lines_added = 1;

    my $test_file = $source_file . '.cfgcheck';

    require Cpanel::Umask;
    my $umask = Cpanel::Umask->new(077);

    open( my $source_fh,    '<', $source_file ) || die "Failed to open conf file for reading: $?";
    open( my $test_file_fh, '>', $test_file )   || die "Failed to open temporary file for writing: $?";

    print $test_file_fh 'Include "' . apache_paths_facade->dir_base() . "/conf.modules.d/*.conf\"\n";

    my $buffer = '';
    while ( read( $source_fh, $buffer, $READ_SIZE ) ) {
        print $test_file_fh $buffer;
        $buffer = '';
    }

    close($test_file_fh);
    close($source_fh);

    return ( $number_of_lines_added, $test_file );
}

1;
