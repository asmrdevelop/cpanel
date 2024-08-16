package Cpanel::Template::Simple;

# cpanel - Cpanel/Template/Simple.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Drop in replacement for Cpanel::Template -- its a low end version of TT
# that has a fast startup time and will survive in a DoS

use strict;

use Cpanel::LoadFile        ();
use Cpanel::Encoder::Tiny   ();    # PPI USE OK - Calling a sub from within a regex :\
use Cpanel::Template::Files ();

our $VERSION = '1.5';

sub process_template {
    my ( $service, $input_hr, $options_hr ) = @_;
    $options_hr ||= {};

    my $error = 'The template file must be given (or the template could not be opened)';
    my $template_file;
    if ( exists $input_hr->{'template_file'} ) {
        if ( !$input_hr->{'template_file'} ) {
            if ( $input_hr->{'print'} ) {
                print 'Template file not defined.';
                return;
            }
            return wantarray ? ( 0, "Template file not defined." ) : 0;
        }
        elsif ( -e $input_hr->{'template_file'} ) {
            $template_file = $input_hr->{'template_file'};
        }
        else {
            return wantarray ? ( 0, "Template file $input_hr->{'template_file'} does not exist." ) : 0;
        }
    }
    else {
        my $error;
        if ( $options_hr->{'branding'} ) {
            ( $template_file, $error ) = Cpanel::Template::Files::get_branding_template_file( $service, $options_hr );
        }
        else {
            ( $template_file, $error ) = Cpanel::Template::Files::get_service_template_file( $service, $options_hr->{'skip_local'}, $input_hr->{'template_name'} );
        }
        if ( !$template_file ) {
            if ( $input_hr->{'print'} ) {
                print $error;
                return;
            }
            return wantarray ? ( 0, $error ) : 0;
        }
    }
    my ( $template_file_data, @status );
    foreach my $line ( split( /\n/, Cpanel::LoadFile::loadfile($template_file) ) ) {
        if ( $line =~ m/\[%-?\s+IF\s+([^%]+)-?%\]/ ) {
            my $query = $1;
            $query =~ s/\s+$//;
            my $result = 0;
            my $op     = '&&';
            foreach my $token ( split( /\s*([\&|\|]+\s*)/, $query ) ) {
                $token =~ s/\s+//g;
                if ( $token eq '&&' ) {
                    last if !$result && $op eq '&&';
                    $op = '&&';
                }
                elsif ( $token eq '||' ) {
                    last if ($result);
                    $op = '||';
                }
                else {
                    my $reverse = ( $token =~ s/!\s*//g ) ? 1 : 0;
                    $result = $input_hr->{$token};
                    $result = $result ? 0 : 1 if $reverse;
                }
            }
            push @status, ( $result ? 1 : 0 );
        }
        elsif ( $line =~ /\[%-?\s+END\s+-?%\]/ ) {
            pop @status;
        }
        elsif ( join( '', @status ) eq "1" x scalar @status ) {
            $template_file_data .= $line . "\n";
        }
    }

    foreach my $key ( keys %$input_hr ) {
        if ( ref $input_hr->{$key} ) {
            foreach my $subkey ( keys %{ $input_hr->{$key} } ) {
                $template_file_data =~ s/\[%-?\s+\Q$key\E\.\Q$subkey\E\s+FILTER\s+html\s+-?%\]/Cpanel::Encoder::Tiny::safe_html_encode_str($input_hr->{$key}->{$subkey})/eg;
                $template_file_data =~ s/\[%-?\s+\Q$key\E\.\Q$subkey\E\s+-?%\]/$input_hr->{$key}->{$subkey}/g;
            }
        }
        else {
            $template_file_data =~ s/\[%-?\s+\Q$key\E\s+FILTER\s+html\s+-?%\]/Cpanel::Encoder::Tiny::safe_html_encode_str($input_hr->{$key})/ge;
            $template_file_data =~ s/\[%-?\s+\Q$key\E\s+-?%\]/$input_hr->{$key}/g;
        }
    }

    if ($template_file_data) {
        if ( $input_hr->{'print'} ) {
            print $template_file_data;
            return 1;
        }
        return wantarray ? ( 1, \$template_file_data ) : \$template_file_data;
    }
    if ( $input_hr->{'print'} ) {
        print "Template Error: $error";
        return;
    }
    return wantarray ? ( 0, "Template Error: $error" ) : 0;
}

1;
