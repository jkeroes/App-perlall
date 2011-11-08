#!perl
use strict;
use warnings;

use Test::More tests => 3;

{
  my $c;
  #my $c = qx{ HARNESS_ACTIVE=1 $^X scripts/perlall --dryrun --skip='5.12*' list };
  #like( $c, qr/perl5.8.9d\n.*?perl5.12.1-nt\n.*?perl5.15.4\@ababab$/m, "skip 5.12*" );

  $c = qx{ HARNESS_ACTIVE=1 $^X scripts/perlall --dryrun --nogit list };
  like( $c, qr/perl5\.8\.9d\n.*?perl5\.12\.1-nt\n.*?perl5\.14\.2$/, "--nogit" );

  $c = qx{ HARNESS_ACTIVE=1 $^X scripts/perlall --dryrun --older=5.12 list };
  like( $c, qr/perl5\.8\.9d$/, "--older" );

  $c = qx{ HARNESS_ACTIVE=1 $^X scripts/perlall --dryrun --newer=5.12.1 list };
  like( $c, qr/perl5\.12\.1-nt\n.*?perl5\.14\.2\n.*?perl5.15.4\@ababab$/, "--older" );
}