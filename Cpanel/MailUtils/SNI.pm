package Cpanel::MailUtils::SNI;

# cpanel - Cpanel/MailUtils/SNI.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $NO_CHECK_SYNTAX = 0;
our $CHECK_SYNTAX    = 1;

my $singleton;

=encoding utf8

=head1 NAME

Cpanel::MailUtils::SNI - Rebuild Dovecot’s SNI configuration file

=head1 SYNOPSIS

    Cpanel::MailUtils::SNI::rebuild_dovecot_sni_conf();

=head1 DISCUSSION

This used to be a much more interesting module: it maintained a map file
that associated domains with key and certificate files.

Now that both Dovecot and Exim use Domain TLS for keys and certs, all this
module is good for is rebuilding Dovecot’s SNI configuration.

=head1 Functions

=over 8

=item B<rebuild_dovecot_sni_conf>

(Re)generates the dovecot SNI include file.

This invokes C<generate_config_file> in Cpanel::AdvConfig, which calls C<Cpanel::AdvConfig::dovecotSNI::get_config> to fetch the proper content to pass to the template processor.

    Cpanel::MailUtils::SNI::rebuild_dovecot_sni_conf();

=cut

sub rebuild_dovecot_sni_conf {
    require Cpanel::AdvConfig::dovecotSNI;
    return Cpanel::AdvConfig::dovecotSNI->new()->rebuild_conf();
}

sub sni_status {
    return 1;    # We no longer support any systems without SNI built in
}

sub is_sni_supported {
    return 1;    # We no longer support any systems without SNI built in
}

=back

=cut

1;
