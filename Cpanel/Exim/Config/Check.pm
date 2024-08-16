package Cpanel::Exim::Config::Check;

# cpanel - Cpanel/Exim/Config/Check.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## no critic qw(TestingAndDebugging::RequireUseStrict TestingAndDebugging::RequireUseWarnings)
use Cpanel::Exim            ();
use Cpanel::SafeRun::Object ();
use Cpanel::LoadFile        ();

sub check_exim_config {
    my @args = @_;
    my ( $self, $config_file, $offset ) = ref( $args[0] ) ? @args : ( {}, @args );

    my $eximbin = ( $self->{'eximbin'} || ( Cpanel::Exim::geteximinfo() )[0] );

    my $goodconf;

    my $run = Cpanel::SafeRun::Object->new(
        'program' => $eximbin,

        # -bV forces exim to do a syntax check and write out the version number to STDOUT
        # -C  alternate config file
        'args' => [ '-bV', '-C', $config_file ]
    );

    if ( $self->{'debug'} ) {
        $self->{'rawout'} = $run->stdout();
    }
    if ( $run->stdout() =~ m/Configuration\s+file\s+is/i ) {
        $goodconf = 1;
    }
    my $error_msg = $run->stderr();
    if ( $run->CHILD_ERROR() ) {
        $goodconf = 0;
    }

    if ($goodconf) {
        if ( !exists $self->{'exim_caps'} ) {
            my ( $exim_bin, $exim_version, $exim_caps ) = Cpanel::Exim::fetch_caps();
            $self->{'exim_caps'} = $exim_caps;
        }
        my $linenum = 0;
        foreach my $line ( split( /\n/, Cpanel::LoadFile::loadfile($config_file) ) ) {
            $linenum++;
            if ( !$self->{'exim_caps'}->{'dkim'} && ( $line =~ m/^\s*dkim_(?:remote_smtp|lookuphost|private_key|canon|selector)/ || $line =~ m/^\s*transport\s*=\s*dkim_/ ) ) {
                $goodconf = 0;
                $error_msg .= "0000-00-00 00:00:00 Exim configuration error in line $linenum of /etc/exim.conf:\n  This version of exim does not support dkim, however dkim specific items were found.\n";
                last;
            }
            elsif ( !$self->{'exim_caps'}->{'domainkeys'} && ( $line =~ m/^\s*dk_(?:remote_smtp|lookuphost|private_key|canon|selector)/ || $line =~ m/^\s*transport\s*=\s*dk_/ ) ) {
                $goodconf = 0;
                $error_msg .= "0000-00-00 00:00:00 Exim configuration error in line $linenum of /etc/exim.conf:\n  This version of exim does not support domainkeys, however domainkeys specific items were found.\n";
                last;
            }
            elsif ( $line =~ m/\s*\$\{perl\s*\{(checkspam2|checkspam2_results|trackbandwidth|trackbandwidth_results)}\s*\}/ ) {
                my $perl_call = $1;
                $goodconf = 0;
                $error_msg .= "0000-00-00 00:00:00 Exim configuration error in line $linenum of /etc/exim.conf:\n  The perl call '$perl_call' is no longer supported in this version of cPanel.\n";
                last;
            }
        }

    }

    if ( !$goodconf ) {
        if ($error_msg) {
            my $line       = 0;
            my @error_msgs = split( /\n/, $error_msg );
            my @cfg_text   = split( /\n/, Cpanel::LoadFile::loadfile($config_file) );
            my @cfg_html   = @cfg_text;
            my $last_error_router_transport;
            for ( my $i = 0; $i <= $#error_msgs; $i++ ) {
                if ( $error_msgs[$i] =~ m/^\s*(\S+)\s+(?:router|transport):\s*$/ ) {
                    $last_error_router_transport = $1;
                }
                if ( $error_msgs[$i] =~ /onfiguration error in line (\d+)/ ) {

                    $line            = $1 - 1;
                    $cfg_html[$line] = "$cfg_html[$line]";
                    $cfg_text[$line] = "==>$cfg_text[$line]<==";

                    if ($offset) {
                        $error_msgs[$i] =~ s/(onfiguration error in line )(\d+)/$1 . ($line = ($2 - $offset))/e;
                    }
                }
            }
            if ( $last_error_router_transport && !$line ) {
                for ( my $i = 0; $i <= $#cfg_text; $i++ ) {
                    if ( $cfg_text[$i] =~ /^\s*$last_error_router_transport\s*:/ ) {
                        $line            = $i;
                        $cfg_html[$line] = "$cfg_html[$line]";
                        $cfg_text[$line] = "==>$cfg_text[$line]<==";
                        $line++;
                        if ($offset) {
                            $line -= $offset;
                        }
                        unshift @error_msgs, "Configuration error in line $line of $config_file:\n";
                    }
                }
            }
            $self->{'rawout'}    .= "\n\nError message from syntax check:\n" . join( "\n", @error_msgs ) . "\n";
            $self->{'error_msg'} .= join( "\n", @error_msgs );
            $self->{'error_line'}      = ( $line + 1 );    #from zero
            $self->{'broken_cfg_html'} = join( "\n", @cfg_html ) . "\n";
            $self->{'broken_cfg_text'} = join( "\n", @cfg_text ) . "\n";
        }
        else {
            $self->{'rawout'} .= "\n\nSyntax check failed.\n";
        }
    }
    $self->{'rawout'} .= "\n";
    return $goodconf;
}
1;
