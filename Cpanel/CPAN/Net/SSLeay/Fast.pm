
package Cpanel::CPAN::Net::SSLeay::Fast;

use strict;
use Net::SSLeay ();

#Copyright (c) 2020 cPanel, L.L.C. <copyright@cpanel.net>
#
#Copyright (c) 1996-2003 Sampo Kellomäki <sampo@symlabs.com>
#
#Copyright (C) 2005-2006 Florian Ragwitz <rafl@debian.org>
#
#Copyright (C) 2005 Mike McCauley <mikem@airspayce.com>
#
#All rights reserved.
#
#Distribution and use of this module is under the same terms as the OpenSSL package itself (i.e. free, but mandatory attribution; NO WARRANTY). Please consult LICENSE file in the root of the Net-SSLeay distribution, and also included in this distribution.
#
#The Authors credit Eric Young and the OpenSSL team with the development of the excellent OpenSSL library, which this Perl package uses.
#
#And remember, you, and nobody else but you, are responsible for auditing this module and OpenSSL library for security problems, backdoors, and general suitability for your application.
# We've added this module to avoid debug code in the upstream version that was slowing execution time

sub ssl_write_all {
    my $ssl      = $_[0];
    my $data_ref = ref $_[1] ? $_[1] : \$_[1];
    my ( $errs, $errno );
    my ( $wrote, $written, $to_write ) = ( 0, 0, Net::SSLeay::blength($$data_ref) );
    if ( $Net::SSLeay::trace > 2 ) {
        my $vm = $Net::SSLeay::trace > 2 && $Net::SSLeay::linux_debug ? ( split ' ', `cat /proc/$$/stat` )[22] : 'vm_unknown';
        warn "  write_all VM at entry=$vm\n";
        warn "partial `$$data_ref'\n" if $Net::SSLeay::trace > 3;
    }
    while ($to_write) {
        $wrote = Net::SSLeay::write_partial( $ssl, $written, $to_write, $$data_ref );
        if ( defined $wrote && ( $wrote > 0 ) ) {    # write_partial can return -1
            $written  += $wrote;
            $to_write -= $wrote;
        }
        else {
            $errno = $!;
            if ( defined $wrote ) {

                # check error conditions via SSL_get_error per man page
                if ( my $sslerr = Net::SSLeay::get_error( $ssl, $wrote ) ) {
                    my $errstr  = Net::SSLeay::ERR_error_string($sslerr);
                    my $errname = '';
                  SWITCH: {
                        $sslerr == Net::SSLeay::constant("ERROR_NONE") && do {

                            # according to map page SSL_get_error(3ssl):
                            #  The TLS/SSL I/O operation completed.
                            #  This result code is returned if and only if ret > 0
                            # so if we received it here complain...
                            warn "ERROR_NONE unexpected with invalid return value!"
                              if $Net::SSLeay::trace;
                            $errname = "SSL_ERROR_NONE";
                        };
                        $sslerr == Net::SSLeay::constant("ERROR_WANT_READ") && do {

                            # operation did not complete, call again later, so do not
                            # set errname and empty err_que since this is a known
                            # error that is expected but, we should continue to try
                            # writing the rest of our data with same io call and params.
                            warn "ERROR_WANT_READ (TLS/SSL Handshake, will continue)\n"
                              if $Net::SSLeay::trace;
                            Net::SSLeay::print_errs('SSL_write(want read)');
                            last SWITCH;
                        };
                        $sslerr == Net::SSLeay::constant("ERROR_WANT_WRITE") && do {

                            # operation did not complete, call again later, so do not
                            # set errname and empty err_que since this is a known
                            # error that is expected but, we should continue to try
                            # writing the rest of our data with same io call and params.
                            warn "ERROR_WANT_WRITE (TLS/SSL Handshake, will continue)\n"
                              if $Net::SSLeay::trace;
                            Net::SSLeay::print_errs('SSL_write(want write)');
                            last SWITCH;
                        };
                        $sslerr == Net::SSLeay::constant("ERROR_ZERO_RETURN") && do {

                            # valid protocol closure from other side, no longer able to
                            # write, since there is no longer a session...
                            warn "ERROR_ZERO_RETURN($wrote): TLS/SSLv3 Closure alert\n"
                              if $Net::SSLeay::trace;
                            $errname = "SSL_ERROR_ZERO_RETURN";
                            last SWITCH;
                        };
                        $sslerr == Net::SSLeay::constant("ERROR_SSL") && do {

                            # library/protocol error
                            warn "ERROR_SSL($wrote): Library/Protocol error occured\n"
                              if $Net::SSLeay::trace;
                            $errname = "SSL_ERROR_SSL";
                            last SWITCH;
                        };
                        $sslerr == Net::SSLeay::constant("ERROR_WANT_CONNECT") && do {

                            # according to man page, should never happen on call to
                            # SSL_write, so complain, but handle as known error type
                            warn "ERROR_WANT_CONNECT: Unexpected error for SSL_write\n"
                              if $Net::SSLeay::trace;
                            $errname = "SSL_ERROR_WANT_CONNECT";
                            last SWITCH;
                        };
                        $sslerr == Net::SSLeay::constant("ERROR_WANT_ACCEPT") && do {

                            # according to man page, should never happen on call to
                            # SSL_write, so complain, but handle as known error type
                            warn "ERROR_WANT_ACCEPT: Unexpected error for SSL_write\n"
                              if $Net::SSLeay::trace;
                            $errname = "SSL_ERROR_WANT_ACCEPT";
                            last SWITCH;
                        };
                        $sslerr == Net::SSLeay::constant("ERROR_WANT_X509_LOOKUP") && do {

                            # operation did not complete: waiting on call back,
                            # call again later, so do not set errname and empty err_que
                            # since this is a known error that is expected but, we should
                            # continue to try writing the rest of our data with same io
                            # call parameter.
                            warn "ERROR_WANT_X509_LOOKUP: (Cert Callback asked for in " . "SSL_write will contine)\n" if $Net::SSLeay::trace;
                            Net::SSLeay::print_errs('SSL_write(want x509');
                            last SWITCH;
                        };
                        $sslerr == Net::SSLeay::constant("ERROR_SYSCALL") && do {

                            # some IO error occured. According to man page:
                            # Check retval, ERR, fallback to errno
                            if ( $wrote == 0 ) {    # EOF
                                warn "ERROR_SYSCALL($wrote): EOF violates protocol.\n"
                                  if $Net::SSLeay::trace;
                                $errname = "SSL_ERROR_SYSCALL(EOF)";
                            }
                            else {                  # -1 underlying BIO error reported.
                                                    # check error que for details, don't set errname since we
                                                    # are directly appending to errs
                                my $chkerrs = Net::SSLeay::print_errs('SSL_write (syscall)');
                                if ($chkerrs) {
                                    warn "ERROR_SYSCALL($wrote): Have errors\n" if $Net::SSLeay::trace;
                                    $errs .= "ssl_write_all $$: 1 - ERROR_SYSCALL($wrote," . "$sslerr,$errstr,$errno)\n$chkerrs";
                                }
                                else {              # que was empty, use errno
                                    warn "ERROR_SYSCALL($wrote): errno($errno)\n" if $Net::SSLeay::trace;
                                    $errs .= "ssl_write_all $$: 1 - ERROR_SYSCALL($wrote," . "$sslerr) : $errno\n";
                                }
                            }
                            last SWITCH;
                        };
                        warn "Unhandled val $sslerr from SSL_get_error(SSL,$wrote)\n"
                          if $Net::SSLeay::trace;
                        $errname = "SSL_ERROR_?($sslerr)";
                    }    # end of SWITCH block
                    if ($errname) {    # if we had an errname set add the error
                        $errs .= "ssl_write_all $$: 1 - $errname($wrote,$sslerr," . "$errstr,$errno)\n";
                    }
                }    # endif on have SSL_get_error val
            }    # endif on $wrote defined
            $errs .= Net::SSLeay::print_errs('SSL_write');
        }    # endelse on $wrote > 0
        if ( $Net::SSLeay::trace > 2 ) {
            my $vm = $Net::SSLeay::linux_debug ? ( split ' ', `cat /proc/$$/stat` )[22] : 'vm_unknown';
            warn "  written so far $wrote:$written bytes (VM=$vm)\n";
        }

        # report if errs exist
        $! = $errno if defined $errno;    ## no critic(Variables::RequireLocalizedPunctuationVars)
        return ( wantarray ? ( undef, $errs ) : undef ) if $errs;
    }
    return wantarray ? ( $written, $errs ) : $written;
}

1;
