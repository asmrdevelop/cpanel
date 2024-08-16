# <@LICENSE>
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to you under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at:
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# </@LICENSE>

=head1 NAME

Mail::SpamAssassin::Plugin::P0f

=head1 SYNOPSIS

  loadplugin     Mail::SpamAssassin::Plugin::P0f
  header         P0F_OS_WINDOWS_XP           X-Passive-Fingerprint-OS =~ m{Windows XP}
  describe       P0F_OS_WINDOWS_XP           Incoming relay is running Windows XP
  score          P0F_OS_WINDOWS_XP           0.7
  header         P0F_OS_WINDOWS              X-Passive-Fingerprint-OS =~ m{Windows}
  describe       P0F_OS_WINDOWS              Incoming relay is running Windows
  score          P0F_OS_WINDOWS              1.0
  header         P0F_OS_FreeBSD              X-Passive-Fingerprint-OS =~ m{FreeBSD}
  describe       P0F_OS_FreeBSD              Incoming relay is running FreeBSD
  score          P0F_OS_FreeBSD              -0.1


=head1 DESCRIPTION

C</etc/mail/spamassassin/P0f.cf>.

=cut

package Mail::SpamAssassin::Plugin::P0f;

use Mail::SpamAssassin::Plugin;
use strict;
use warnings;
use bytes;
use re 'taint';    ## no critic(ProhibitEvilModules)

BEGIN {
    local @INC = ( '/usr/local/cpanel', @INC );
    require Cpanel::Net::P0f;
}

use vars qw(@ISA);
@ISA = qw(Mail::SpamAssassin::Plugin);

sub extract_metadata {
    my ( $self, $opts ) = @_;

    my $mail_spam_message = $opts->{'msg'};

    Mail::SpamAssassin::Plugin::dbg("Checking P0f");
    foreach my $untrusted_relay ( @{ $mail_spam_message->{'metadata'}{'relays_untrusted'} } ) {    # Mail::SpamAssassin::Message
                                                                                                   # $untrusted_relay->{helo}
                                                                                                   # $untrusted_relay->{ip}

        my $fingerprint;
        eval { $fingerprint = Cpanel::Net::P0f->new()->lookup_address( $untrusted_relay->{'ip'} ) };
        if ($fingerprint) {
            my $os_name_flavor = $fingerprint->get('os_name') . ' ' . ( $fingerprint->get('os_flavor') || '' );
            $os_name_flavor =~ s/\s+$//;
            $mail_spam_message->put_metadata( 'X-Passive-Fingerprint-OS' => $os_name_flavor );
            Mail::SpamAssassin::Plugin::dbg( "metadata: X-Passive-Fingerprint-OS: " . $os_name_flavor );
            $mail_spam_message->put_metadata( 'X-Passive-Fingerprint-Link' => $fingerprint->get('link_type') );
            Mail::SpamAssassin::Plugin::dbg( "metadata: X-Passive-Fingerprint-Link: " . $fingerprint->get('link_type') );

            last;
        }
        else {
            Mail::SpamAssassin::Plugin::dbg("No fingerprint: $@");
        }
    }

    return 1;
}
1;
