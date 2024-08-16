package Cpanel::Exim::Config::Logselector;

# cpanel - Cpanel/Exim/Config/Logselector.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub set_log_selector_option {
    my ($cfg) = @_;

    my @mandatory = mandatory_options();
    my @default   = default_options();

    my $comment = "# " . join( ', ', @mandatory ) . " are needed for cPanel email tracking.\n";
    $comment .= "# " . join( ', ', @default ) . " are suggested settings that may be disabled.\n";
    if ( $cfg->{'CONFIG'} =~ m/^\s*log_selector\s*=\s*(.*)/m ) {
        my $current_opts = $1;
        my %options      = map { $_ => undef } split( /\s+/, $current_opts );

        # remove negative mandatory option
        delete $options{ _reverse_option($_) } for @mandatory;
        unless ( exists $options{'+all'} ) {

            # set mandatory options
            $options{$_} = undef for @mandatory;
            for (@default) {
                $options{$_} = undef unless exists $options{ _reverse_option($_) };
            }
        }
        my $str = join( ' ', sort { $a cmp $b } keys %options );
        $cfg->{'CONFIG'} =~ s/^\s*log_selector\s*=.*/${comment}log_selector = $str/gm;
        return;
    }

    # add default settings for log_selector
    $cfg->{'CONFIG'} .= "\n${comment}log_selector = " . join( ' ', @mandatory, @default ) . "\n\n";
    return;
}

# whatever happen these option will be added
sub mandatory_options {

    # +incoming_port   needed for identify_local_connection
    # +smtp_connection needed to purge get_recent_authed_mail_ips_domain
    # +all_parents     needed to resolve forwarders
    return qw{+incoming_port +smtp_connection +all_parents};
}

# except if the opposite is set these options will be added
sub default_options {

    # +retry_defer : useful for debugging smarthost issues
    # +subject, +arguments, +received_recipients : good default per case 57735
    return qw{+retry_defer +subject +arguments +received_recipients};
}

sub _reverse_option {
    my $opt = shift;
    return unless ( $opt && $opt =~ /^([+-])([a-z_]+)$/ );
    my ( $sign, $word ) = ( $1, $2 );
    $sign = $sign eq '+' ? '-' : '+';
    return $sign . $word;
}

1;
