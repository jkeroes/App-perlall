package Devel::PatchPerl::Plugin::Asan;
use base 'Devel::PatchPerl';

=head1 DESCRIPTION

Plugin for Devel::PatchPerl to fix several buffer overflows and use-after-free
bugs in production perls which prevent compilations with C<clang AddressSanitizer>,
aka I<asan>.

Note that F<buildperl.pl> from L<Devel::PPPerl> and L<Devel::PatchPerl> do
not provide such security patches, only configure and make patches.

Most fixes have very low security impact. No known exploits do exist.

You need to run C<perlall build --allpatches> or C<perlall build --patches=Asan>
to apply these.

=head1 PATCHES

The list is complete for non-threaded perls. 
For threaded perls some more patches need to be added.

    5.8.2-5.16.2: CVE-2013-1667 prevent hsplit DOS attacks
    5.10-5.15.9:  RT#111586 sdbm.c off-by-one access to global .dir
    5.12-5.16.0:  RT#72700 List::Util boot Fix off-by-two on string literal length
    5.15.4-9, 5.17.0-6: RT#115702 overlapping memcpy in to_utf8_case
    5.6-5.16.0:   RT#111594 Socket::unpack_sockaddr_un heap-buffer-overflow
    5.8-5.14.3:   RT#115992 PL_eval_start use-after-free
    5.10-5.14.3:  RT#115994 S_join_exact global-buffer-overflow
    5.17.7-8:     RT#82119 Socket::inet_ntop heap-buffer-overflow
    5.14.0-3:     RT#91678 S_anonymise_cv_maybe UTF8 cleanup
    5.17,18.0,19  RT#118525 Return B::HEK for B::CV::GV of lexical subs

=head2 Devel::PatchPerl::Plugin::Asan::patchperl($class, {version,source,patchexe})

Apply patches in Devel::PatchPerl::Plugin::Asan depending on the
perl version. See L<Devel::PatchPerl::Plugin>.

Every patch is recorded in patchlevel.h, visible in myconfig.
If a patch fails the script dies.

=cut

sub patchperl {
  my $class = shift;
  my %args = @_;
  my ($vers, $source, $patch_exe) = @args{qw(version source patchexe)};
  for my $p ( grep { Devel::PatchPerl::_is( $_->{perl}, $vers ) } @Devel::PatchPerl::patch ) {
    for my $s (@{$p->{subs}}) {
      my ($sub, @args) = @$s;
      push @args, $vers unless scalar @args;
      $sub->(@args);
    }
  }
}


package
  Devel::PatchPerl;

use File::Copy;
use vars '@patch';

@patch = (
  {
    perl => [ qr/^5\.1[01]\.\d$/ ],
    # fixed in 5.16.0
    subs => [ [ \&_patch_sdbm] ],
  },
  {
    perl => [ qr/^5\.12\.[0-5]$/,
              qr/^5\.1[35]\.\d$/,
              qr/^5\.14\.[0-3]$/,
            ],
    subs => [ [ \&_patch_listutil_boot ], [ \&_patch_sdbm] ],
  },
  {
    perl => [ qr/^5\.16\.0$/ ],
    # fixed in 5.16.1
    subs => [ [ \&_patch_listutil_boot ] ],
  },
  {
    perl => [ qr/^5\.15\.[4-9]$/,
              qr/^5\.17\.[0-6]$/ ],
    # fixed in 5.17.6
    subs => [ [ \&_patch_to_utf8_case_memcpy ] ],
  },
  {
    perl => [ qr/^5\.[6-9].\d$/,
	      qr/^5\.1[0-5].\d$/,
              qr/^5\.16\.0$/ ],
    # fixed in 5.16.1
    subs => [ [ \&_patch_socket_un ] ],
  },
  {
    perl => [ qr/^5\.1[0123]\.\d$/,
              qr/^5\.15\.[012]$/,    # fixed in 5.15.3
	      qr/^5\.14\.[0123]$/ ], # to be fixed in 5.14.4
    subs => [ [ \&_patch_eval_start_510] ],
  },
  {
    perl => [ qr/^5\.8\.\d$/ ],
    subs => [ [ \&_patch_eval_start_58] ],
  },
  {
    perl => [ qr/^5\.1[0123]\.\d$/,  # broken since 5.10 (at least)
              qr/^5\.15\.0$/,        # fixed in 5.15.1
	      qr/^5\.14\.[0123]$/ ], # to be fixed in 5.14.4
    subs => [ [ \&_patch_join_exact] ],
  },
  {
    perl => [ qr/^5\.17\.[78]$/ ],
    # broken in 5.17.8, 2.006-2.007
    subs => [ [ \&_patch_socket_inet_ntop ] ],
  },
  {
    perl => [ qr/^5\.14\.[0123]$/,
              qr/^5\.15\.[012]$/ ],
    # regression in 5.14, fixed in v5.15.3-232-g1bac5ec
    subs => [ [ \&_patch_anonymise_cv_maybe ] ],
  },
  {
    perl => [ 
      qr/^5\.16\.[012]$/,  # fixed in 5.16.3
      qr/^5\.14\.[0123]$/, # fixed in 5.14.4
      qr/^5\.1[01235]\./,  # TODO fixes not backported
      qr/^5\.8[23456789]\./, # TODO
      ],
    # d59e31fc729d8a39a774f03bc6bc457029a7aef2 CVE-2013-1667
    subs => [ [ \&_patch_hsplit_rehash ] ],
  },
  {
    perl => [ 
      qr/^5\.16\.[012]$/,  # fixed in 5.16.3
      qr/^5\.14\.[0123]$/, # fixed in 5.14.4
      qr/^5\.1[01235]\./,  # 
      ],
    subs => [ [ \&_patch_regcomp_nothing ] ],
  },
  #{
  #  perl => [
  #    qr/^5\.1[789]/,  # RT #118525
  #    ],
  #  subs => [ [ \&_patch_cvgv_lexsub ] ],
  #},
);

sub _add_patchlevel {
  my $vers = shift;
  my $line = shift;
  my $success;
  File::Copy::cp("patchlevel.h", "patchlevel.h.orig");
  open my $in, "<", "patchlevel.h.orig" or return;
  open my $out, ">", "patchlevel.h" or return;
  $line =~ s/"/\"/g;
  my $qr = $] > 5.010 ? /^\s+PERL_GIT_UNPUSHED_COMMITS/
                      : /^\tNULL$/;
  while (my $s = <$in>) {
    print $out $s;
    if ($s =~ $qr) {
      $success++;
      print $out "\t,\"".$line."\"\n";
    }
  }
  close $in;
  close $out;
  print STDERR "patched: $line\n";
  return $success;
}

sub _patch_listutil_boot
{
  # RT#72700 Fix off-by-two on string literal length
  _patch(<<'END');
--- cpan/List-Util/ListUtil.xs.orig	2012-11-12 10:41:07.000000000 -0600
+++ cpan/List-Util/ListUtil.xs	2012-11-12 10:47:52.943198199 -0600
@@ -600,7 +600,7 @@
     varav = GvAVn(vargv);
 #endif
     if (SvTYPE(rmcgv) != SVt_PVGV)
-	gv_init(rmcgv, lu_stash, "List::Util", 12, TRUE);
+	gv_init(rmcgv, lu_stash, "List::Util", 10, TRUE);
     rmcsv = GvSVn(rmcgv);
 #ifndef SvWEAKREF
     av_push(varav, newSVpv("weaken",6));
END

  _add_patchlevel(@_, "RT#72700 List::Util boot Fix off-by-two on string literal length");
}

sub _patch_sdbm
{
  # acdbe25bd91bf897e0cf373b9
  # RT#111586 sdbm.c off-by-one access to global .dir
  _patch(<<'END');
--- ext/SDBM_File/sdbm/sdbm.c.orig	2012-11-12 10:53:26.000000000 -0600
+++ ext/SDBM_File/sdbm/sdbm.c		2012-11-12 10:56:02.790350262 -0600
@@ -78,8 +78,8 @@ sdbm_open(register char *file, register int flags, register int mode)
 	register char *dirname;
 	register char *pagname;
 	size_t filelen;
-	const size_t dirfext_len = sizeof(DIRFEXT "");
-	const size_t pagfext_len = sizeof(PAGFEXT "");
+	const size_t dirfext_size = sizeof(DIRFEXT "");
+	const size_t pagfext_size = sizeof(PAGFEXT "");
 
 	if (file == NULL || !*file)
 		return errno = EINVAL, (DBM *) NULL;
@@ -88,17 +88,17 @@ sdbm_open(register char *file, register int flags, register int mode)
  */
 	filelen = strlen(file);
 
-	if ((dirname = (char *) malloc(filelen + dirfext_len + 1
-				       + filelen + pagfext_len + 1)) == NULL)
+	if ((dirname = (char *) malloc(filelen + dirfext_size
+				       + filelen + pagfext_size)) == NULL)
 		return errno = ENOMEM, (DBM *) NULL;
 /*
  * build the file names
  */
 	memcpy(dirname, file, filelen);
-	memcpy(dirname + filelen, DIRFEXT, dirfext_len + 1);
-	pagname = dirname + filelen + dirfext_len + 1;
+	memcpy(dirname + filelen, DIRFEXT, dirfext_size);
+	pagname = dirname + filelen + dirfext_size;
 	memcpy(pagname, file, filelen);
-	memcpy(pagname + filelen, PAGFEXT, pagfext_len + 1);
+	memcpy(pagname + filelen, PAGFEXT, pagfext_size);
 
 	db = sdbm_prep(dirname, pagname, flags, mode);
 	free((char *) dirname);
END

  _add_patchlevel(@_, "RT#111586 sdbm.c off-by-one access to global .dir");
}

sub _patch_to_utf8_case_memcpy
{
  _patch(<<'END');
--- utf8.c~
+++ utf8.c
@@ -2366,7 +2366,9 @@ Perl_to_utf8_case(pTHX_ const U8 *p, U8* ustrp, STRLEN *lenp,
     /* Here, there was no mapping defined, which means that the code point maps
      * to itself.  Return the inputs */
     len = UTF8SKIP(p);
-    Copy(p, ustrp, len, U8);
+    if (p != ustrp) {   /* RT#115702 Don't copy onto itself */
+        Copy(p, ustrp, len, U8);
+    }
 
     if (lenp)
         *lenp = len;
END

  _add_patchlevel(@_, "RT#115702 overlapping memcpy in to_utf8_case");
}

sub _patch_socket_un
{
  my $vers = shift;
  my $patch = <<'END';
commit e5086424505dcbfc5e26aeb984b769ecf5ffed01
Author: David Mitchell <davem@iabyn.com>
Date:   Sun Feb 24 16:46:19 2013 +0000
   
On Linux sockaddrlen on sockets returned by accept, recvfrom,
getpeername and getsockname is not equal to sizeof(addr).
A (fairly harmless) read buffer overflow can occur when copying sockaddr
buffers on linux. Cherry-pick the fix from Socket 2.009 to keep ASAN happy.

--- ext/Socket/Socket.xs~
+++ ext/Socket/Socket.xs
@@ -565,10 +565,16 @@ unpack_sockaddr_un(sun_sv)
 			"Socket::unpack_sockaddr_un",
 			sockaddrlen, sizeof(addr));
 	}
+#   else
+	if (sockaddrlen < sizeof(addr)) { /* RT #111594 */
+           Copy(sun_ad, &addr, sockaddrlen, char);
+           Zero(((char*)&addr) + sockaddrlen, sizeof(addr) - sockaddrlen, char);
+       }
+       else {
+           Copy(sun_ad, &addr, sizeof(addr), char);
+       }
 #   endif
 
-	Copy( sun_ad, &addr, sizeof addr, char );
-
 	if ( addr.sun_family != AF_UNIX ) {
 	    croak("Bad address family for %s, got %d, should be %d",
 			"Socket::unpack_sockaddr_un",
END

  #; )
  if ($vers =~ /^5\.6\./) {
    $patch =~ s/@@ -565,10 +565,16 @@/@@ -1016,10 +1016,16 @@/;
  }
  if ($vers =~ /^5\.[89]\./ or $vers =~ /^5\.1[0-2]\./) {
    $patch =~ s/@@ -565,10 +565,16 @@/@@ -363,10 +363,16 @@/;
  }
  if ($vers =~ /^5\.16\./ or $vers =~ /^5\.15\.[5-9]\./) {
    $patch =~ s|ext/Socket/Socket.xs|cpan/Socket/Socket.xs|g;
  }
  _patch($patch);

  _add_patchlevel($vers, "RT#111594 Socket::unpack_sockaddr_un heap-buffer-overflow");
}

sub _patch_eval_start_510
{
  _patch(<<'END');
--- pp_ctl.c~
+++ pp_ctl.c
@@ -3088,6 +3088,7 @@ Perl_sv_compile_2op_is_broken(pTHX_ SV *sv, OP **startop, const char *code,
     CV* runcv = NULL;	/* initialise to avoid compiler warnings */
     STRLEN len;
     bool need_catch;
+    OP* ret;
 
     PERL_ARGS_ASSERT_SV_COMPILE_2OP_IS_BROKEN;
 
@@ -3182,7 +3183,9 @@ Perl_sv_compile_2op_is_broken(pTHX_ SV *sv, OP **startop, const char *code,
     PERL_UNUSED_VAR(newsp);
     PERL_UNUSED_VAR(optype);
 
-    return PL_eval_start;
+    ret = PL_eval_start;
+    PL_eval_start = NULL;
+    return ret;
 }
 
 
@@ -3903,8 +3906,10 @@ PP(pp_require)
     encoding = PL_encoding;
     PL_encoding = NULL;
 
-    if (doeval(gimme, NULL, NULL, PL_curcop->cop_seq))
+    if (doeval(gimme, NULL, NULL, PL_curcop->cop_seq)) {
 	op = DOCATCH(PL_eval_start);
+	PL_eval_start = NULL;
+    }
     else
 	op = PL_op->op_next;
 
@@ -4029,6 +4034,7 @@ PP(pp_entereval)
     PUTBACK;
 
     if (doeval(gimme, NULL, runcv, seq)) {
+	OP *ret;
 	if (was != PL_breakable_sub_gen /* Some subs defined here. */
 	    ? (PERLDB_LINE || PERLDB_SAVESRC)
 	    :  PERLDB_SAVESRC_NOSUBS) {
@@ -4037,7 +4043,9 @@ PP(pp_entereval)
 	    char *const safestr = savepvn(tmpbuf, len);
 	    SAVEDELETE(PL_defstash, safestr, len);
 	}
-	return DOCATCH(PL_eval_start);
+	ret = DOCATCH(PL_eval_start);
+	PL_eval_start = NULL;
+	return ret;
     } else {
 	/* We have already left the scope set up earlier thanks to the LEAVE
 	   in doeval().  */
END

  _add_patchlevel(@_, "RT#115992 PL_eval_start use-after-free");
}

sub _patch_eval_start_58
{
  _patch(<<'END');
diff -bu ./pp_ctl.c~ ./pp_ctl.c
--- ./pp_ctl.c~	2013-03-04 18:45:25.823223519 -0600
+++ ./pp_ctl.c	2013-03-04 18:52:26.691549451 -0600
@@ -2839,7 +2839,7 @@ STATIC OP *
 S_doeval(pTHX_ int gimme, OP** startop, CV* outside, U32 seq)
 {
     dSP;
-    OP * const saveop = PL_op;
+    OP * saveop = PL_op;
 
     PL_in_eval = ((saveop && saveop->op_type == OP_REQUIRE)
 		  ? (EVAL_INREQUIRE | (PL_in_eval & EVAL_INEVAL))
@@ -2985,7 +2985,9 @@ S_doeval(pTHX_ int gimme, OP** startop, CV* outside, U32 seq)
     MUTEX_UNLOCK(&PL_eval_mutex);
 #endif /* USE_5005THREADS */
 
-    RETURNOP(PL_eval_start);
+    saveop = PL_eval_start;
+    PL_eval_start = NULL;
+    RETURNOP(saveop);
 }
 
 STATIC PerlIO *
@@ -3426,7 +3428,12 @@ PP(pp_require)
     encoding = PL_encoding;
     PL_encoding = Nullsv;
 
-    op = DOCATCH(doeval(gimme, NULL, Nullcv, PL_curcop->cop_seq));
+   if (doeval(gimme, NULL, Nullcv, PL_curcop->cop_seq)) {
+ 	op = DOCATCH(PL_eval_start);
+	PL_eval_start = NULL;
+   }
+   else
+       op = PL_op->op_next;
 
     /* Restore encoding. */
     PL_encoding = encoding;
END

  _add_patchlevel(@_, "RT#115992 PL_eval_start use-after-free");
}

sub _patch_join_exact
{
# commit bb789b09de07edfb74477eb1603949c96d60927d
# Author:     David Mitchell <davem@iabyn.com>
# AuthorDate: Tue Jul 5 11:35:08 2011 +0100
# 
#     fix segv in regcomp.c:S_join_exact()
#     
#     This function joins multiple EXACT* nodes into a single node.
#     At the end, under DEBUGGING, it marks the optimised-out nodes as being
#     type OPTIMIZED. However, some of the 'nodes' aren't actually nodes;
#     they're random bits of string at the tail of those nodes. So you
#     can't peek that the 'node's OP field to decide what type it was.
#     
#     Instead, just unconditionally overwrite all the slots with fake
#     OPTIMIZED nodes.
  _patch(<<'END');
--- regcomp.c~
+++ regcomp.c
@@ -2647,13 +2647,17 @@ S_join_exact(pTHX_ RExC_state_t *pRExC_state, regnode *scan, I32 *min, U32 flags
     }
     
 #ifdef DEBUGGING
-    /* Allow dumping */
+    /* Allow dumping but overwriting the collection of skipped
+     * ops and/or strings with fake optimized ops */
     n = scan + NODE_SZ_STR(scan);
     while (n <= stop) {
-        if (PL_regkind[OP(n)] != NOTHING || OP(n) == NOTHING) {
-            OP(n) = OPTIMIZED;
-            NEXT_OFF(n) = 0;
-        }
+	OP(n) = OPTIMIZED;
+#ifdef FLAGS
+	FLAGS(n) = 0;
+#else
+	n->flags = 0;
+#endif
+	NEXT_OFF(n) = 0;
         n++;
     }
 #endif
END

  _add_patchlevel(@_, "RT#115994 S_join_exact global-buffer-overflow");
}

sub _patch_socket_inet_ntop
{
  my $vers = shift;
  my $patch = <<'END';
--- cpan/Socket/Socket.xs~
+++ cpan/Socket/Socket.xs
@@ -934,8 +934,13 @@ inet_ntop(af, ip_address_sv)
 #endif
 		      "Socket::inet_ntop", af);
 	}
-
-	Copy(ip_address, &addr, sizeof addr, char);
+	if (addrlen < sizeof(addr)) {
+	   Copy(ip_address, &addr, addrlen, char);
+           Zero(((char*)&addr)+addrlen, sizeof(addr) - addrlen, char);
+	}
+	else {
+	  Copy(ip_address, &addr, sizeof addr, char);
+	}
 	inet_ntop(af, &addr, str, sizeof str);
 
 	ST(0) = sv_2mortal(newSVpvn(str, strlen(str)));
END

  #; )
  _patch($patch);
  _add_patchlevel($vers, "RT#82119 Socket::inet_ntop heap-buffer-overflow");
}

sub _patch_anonymise_cv_maybe
{
  my $vers = shift;
  my $patch = <<'END';
commit 1bac5ecc108e6bb05752e5aef66c6890163aff39
Author: Brian Fraser <fraserbn@gmail.com>
Date:   Mon Sep 26 13:48:52 2011 -0700

    sv.c: S_anonymise_cv_maybe UTF8 cleanup.

diff --git a/sv.c b/sv.c
index d71f901..a3a2c74 100644
--- sv.c.orig
+++ sv.c
@@ -5893,7 +5893,6 @@ Perl_sv_replace(pTHX_ register SV *const sv, register SV *const nsv)
 STATIC void
 S_anonymise_cv_maybe(pTHX_ GV *gv, CV* cv)
 {
-    char *stash;
     SV *gvname;
     GV *anongv;
 
@@ -5913,10 +5912,10 @@ S_anonymise_cv_maybe(pTHX_ GV *gv, CV* cv)
     }
 
     /* if not, anonymise: */
-    stash  = GvSTASH(gv) && HvNAME(GvSTASH(gv))
-              ? HvENAME(GvSTASH(gv)) : NULL;
-    gvname = Perl_newSVpvf(aTHX_ "%s::__ANON__",
-					stash ? stash : "__ANON__");
+    gvname = (GvSTASH(gv) && HvNAME(GvSTASH(gv)) && HvENAME(GvSTASH(gv)))
+                    ? newSVhek(HvENAME_HEK(GvSTASH(gv)))
+                    : newSVpvn_flags( "__ANON__", 8, 0 );
+    sv_catpvs(gvname, "::__ANON__");
     anongv = gv_fetchsv(gvname, GV_ADDMULTI, SVt_PVCV);
     SvREFCNT_dec(gvname);
 
END

  #; )
  _patch($patch);
  _add_patchlevel($vers, "RT#91678 S_anonymise_cv_maybe UTF8 cleanup");
}

sub _patch_cvgv_lexsub
{
  my $vers = shift;
  my $patch = <<'END';
From 5e135b6d655cf605ed3d659b94eef847e7d5d29c Mon Sep 17 00:00:00 2001
From: Reini Urban <rurban@x-ray.at>
Date: Thu, 11 Jul 2013 12:09:15 -0500
Subject: [PATCH] [perl #118525] Return B::HEK for B::CV::GV of lexical subs

A lexsub has a hek instead of a gv.
Provide a ref to a PV for the name in the new B::HEK class.
This crashed previously accessing the not existing SvFLAGS of the hek.
---
 ext/B/B.pm    |   27 ++++++++++++++++++++++++++-
 ext/B/B.xs    |   42 +++++++++++++++++++++++++++++++++++++++++-
 ext/B/typemap |   12 ++++++++++++
 3 files changed, 79 insertions(+), 2 deletions(-)

diff ext/B/B.pm~ ext/B/B.pm
index 8b13dea..c153899 100644
--- ext/B/B.pm~
+++ ext/B/B.pm
@@ -1265,6 +1267,29 @@ rather than a list of all of them.
 
 =back
 
+=head2 B::HEK Methods
+
+A B::HEK is returned by B::CV->GV for a lexical sub, defining its name.
+Using the dereferenced scalar value of the object returns the string value,
+which is usually enough; the other methods are rarely needed.
+
+    use B;
+    use feature 'lexical_subs';
+    my sub p {1};
+    $cv = B::svref_2object(\&p);
+    $hek = $cv->GV;
+    print $$hek, "==", $hek->KEY;
+
+=over 4
+
+=item KEY
+
+=item LEN
+
+=item FLAGS
+
+=back
+
 =head2 $B::overlay
 
 Although the optree is read-only, there is an overlay facility that allows
diff ext/B/B.xs~ ext/B/B.xs
index fbe6be6..444d2fe 100644
--- ext/B/B.xs~
+++ ext/B/B.xs
@@ -296,6 +296,17 @@ make_sv_object(pTHX_ SV *sv)
 }
 
 static SV *
+make_hek_object(pTHX_ HEK *hek)
+{
+  SV *ret = sv_setref_pvn(sv_newmortal(), "B::HEK", HEK_KEY(hek), HEK_LEN(hek));
+  SV *rv = SvRV(ret);
+  SvIOKp_on(rv);
+  SvIV_set(rv, PTR2IV(hek));
+  SvREADONLY_on(rv);
+  return ret;
+}
+
+static SV *
 make_temp_object(pTHX_ SV *temp)
 {
     SV *target;
@@ -602,6 +613,7 @@ typedef IO	*B__IO;
 
 typedef MAGIC	*B__MAGIC;
 typedef HE      *B__HE;
+typedef HEK     *B__HEK;
 typedef struct refcounted_he	*B__RHE;
 #ifdef PadlistARRAY
 typedef PADLIST	*B__PADLIST;
@@ -1390,7 +1402,10 @@ IVX(sv)
 	ptr = (ix & 0xFFFF) + (char *)SvANY(sv);
 	switch ((U8)(ix >> 16)) {
 	case (U8)(sv_SVp >> 16):
-	    ret = make_sv_object(aTHX_ *((SV **)ptr));
+            if ((ix == (PVCV_gv_ix)) && CvNAMED(sv))
+                ret = make_hek_object(aTHX_ CvNAME_HEK((CV*)sv));
+            else
+	        ret = make_sv_object(aTHX_ *((SV **)ptr));
 	    break;
 	case (U8)(sv_IVp >> 16):
 	    ret = sv_2mortal(newSViv(*((IV *)ptr)));
@@ -1588,6 +1603,31 @@ PV(sv)
         }
 	ST(0) = newSVpvn_flags(p, len, SVs_TEMP | utf8);
 
+MODULE = B	PACKAGE = B::HEK
+
+void
+KEY(hek)
+        B::HEK   hek
+    ALIAS:
+	LEN = 1
+	FLAGS = 2
+    PPCODE:
+        SV *pv;
+	switch (ix) {
+	case 0:
+            pv = newSVpvn(HEK_KEY(hek), HEK_LEN(hek));
+            if (HEK_UTF8(hek)) SvUTF8_on(pv);
+            SvREADONLY_on(pv);
+            PUSHs(pv);
+            break;
+        case 1:
+            mPUSHu(HEK_LEN(hek));
+            break;
+        case 2:
+            mPUSHu(HEK_FLAGS(hek));
+            break;
+        }
+
 MODULE = B	PACKAGE = B::PVMG
 
 void
diff ext/B/typemap~ ext/B/typemap
index e97fb76..88de4da 100644
--- ext/B/typemap~
+++ ext/B/typemap
@@ -35,6 +35,7 @@ PADOFFSET	T_UV
 
 B::HE		T_HE_OBJ
 B::RHE		T_RHE_OBJ
+B::HEK		T_HEK_OBJ
 
 B::PADLIST	T_PL_OBJ
 
@@ -79,6 +80,14 @@ T_RHE_OBJ
 	else
 	    croak(\"$var is not a reference\")
 
+T_HEK_OBJ
+	if (SvROK($arg)) {
+	    IV tmp = SvIV((SV*)SvRV($arg));
+	    $var = INT2PTR($type,tmp);
+	}
+	else
+	    croak(\"$var is not a reference\")
+
 T_PL_OBJ
 	if (SvROK($arg)) {
 	    IV tmp = SvIV((SV*)SvRV($arg));
@@ -94,6 +103,9 @@ T_MG_OBJ
 T_HE_OBJ
 	sv_setiv(newSVrv($arg, "B::HE"), PTR2IV($var));
 
+T_HEK_OBJ
+	sv_setiv(newSVrv($arg, "B::HEK"), PTR2IV($var));
+
 T_RHE_OBJ
 	sv_setiv(newSVrv($arg, "B::RHE"), PTR2IV($var));
 
-- 
1.7.10.4
END

  #; )
  _patch($patch);
  _add_patchlevel($vers, "RT#118525 Return B::HEK for B::CV::GV of lexical subs");
}

sub _patch_hsplit_rehash
{
  my $vers = shift;
  my $patch = <<'END';
commit d59e31fc729d8a39a774f03bc6bc457029a7aef2
Author: Yves Orton <demerphq@gmail.com>
Date:   Tue Feb 12 10:53:05 2013 +0100

    Prevent premature hsplit() calls, and only trigger REHASH after hsplit()
    
    Triggering a hsplit due to long chain length allows an attacker
    to create a carefully chosen set of keys which can cause the hash
    to use 2 * (2**32) * sizeof(void *) bytes ram. AKA a DOS via memory
    exhaustion. Doing so also takes non trivial time.
    
    Eliminating this check, and only inspecting chain length after a
    normal hsplit() (triggered when keys>buckets) prevents the attack
    entirely, and makes such attacks relatively benign.
    
    (cherry picked from commit f1220d61455253b170e81427c9d0357831ca0fac)

diff --git a/ext/Hash-Util-FieldHash/t/10_hash.t b/ext/Hash-Util-FieldHash/t/10_hash.t
index 2cfb4e8..d58f053 100644
--- ext/Hash-Util-FieldHash/t/10_hash.t~
+++ ext/Hash-Util-FieldHash/t/10_hash.t
@@ -38,15 +38,29 @@ use constant START     => "a";
 
 # some initial hash data
 fieldhash my %h2;
-%h2 = map {$_ => 1} 'a'..'cc';
+my $counter= "a";
+$h2{$counter++}++ while $counter ne 'cd';
 
 ok (!Internals::HvREHASH(%h2), 
     "starting with pre-populated non-pathological hash (rehash flag if off)");
 
 my @keys = get_keys(\%h2);
+my $buckets= buckets(\%h2);
 $h2{$_}++ for @keys;
+$h2{$counter++}++ while buckets(\%h2) == $buckets; # force a split
 ok (Internals::HvREHASH(%h2), 
-    scalar(@keys) . " colliding into the same bucket keys are triggering rehash");
+    scalar(@keys) . " colliding into the same bucket keys are triggering rehash after split");
+
+# returns the number of buckets in a hash
+sub buckets {
+    my $hr = shift;
+    my $keys_buckets= scalar(%$hr);
+    if ($keys_buckets=~m!/([0-9]+)\z!) {
+        return 0+$1;
+    } else {
+        return 8;
+    }
+}
 
 sub get_keys {
     my $hr = shift;
diff --git a/hv.c b/hv.c
index 2be1feb..abb9d76 100644
--- hv.c~
+++ hv.c
@@ -35,7 +35,8 @@ holds the key and hash value.
 #define PERL_HASH_INTERNAL_ACCESS
 #include "perl.h"
 
-#define HV_MAX_LENGTH_BEFORE_SPLIT 14
+#define HV_MAX_LENGTH_BEFORE_REHASH 14
+#define SHOULD_DO_HSPLIT(xhv) ((xhv)->xhv_keys > (xhv)->xhv_max) /* HvTOTALKEYS(hv) > HvMAX(hv) */
 
 static const char S_strtab_error[]
     = "Cannot modify shared string table in hv_%s";
@@ -794,29 +795,9 @@ Perl_hv_common(pTHX_ HV *hv, SV *keysv, const char *key, STRLEN klen,
     if (masked_flags & HVhek_ENABLEHVKFLAGS)
 	HvHASKFLAGS_on(hv);
 
-    {
-	const HE *counter = HeNEXT(entry);
-
-	xhv->xhv_keys++; /* HvTOTALKEYS(hv)++ */
-	if (!counter) {				/* initial entry? */
-	} else if (xhv->xhv_keys > xhv->xhv_max) {
-		/* Use only the old HvKEYS(hv) > HvMAX(hv) condition to limit
-		   bucket splits on a rehashed hash, as we're not going to
-		   split it again, and if someone is lucky (evil) enough to
-		   get all the keys in one list they could exhaust our memory
-		   as we repeatedly double the number of buckets on every
-		   entry. Linear search feels a less worse thing to do.  */
-	    hsplit(hv);
-	} else if(!HvREHASH(hv)) {
-	    U32 n_links = 1;
-
-	    while ((counter = HeNEXT(counter)))
-		n_links++;
-
-	    if (n_links > HV_MAX_LENGTH_BEFORE_SPLIT) {
-		hsplit(hv);
-	    }
-	}
+    xhv->xhv_keys++; /* HvTOTALKEYS(hv)++ */
+    if ( SHOULD_DO_HSPLIT(xhv) ) {
+        hsplit(hv);
     }
 
     if (return_svp) {
@@ -1192,7 +1173,7 @@ S_hsplit(pTHX_ HV *hv)
 
 
     /* Pick your policy for "hashing isn't working" here:  */
-    if (longest_chain <= HV_MAX_LENGTH_BEFORE_SPLIT /* split worked?  */
+    if (longest_chain <= HV_MAX_LENGTH_BEFORE_REHASH /* split worked?  */
 	|| HvREHASH(hv)) {
 	return;
     }
@@ -2831,8 +2812,8 @@ S_share_hek_flags(pTHX_ const char *str, I32 len, register U32 hash, int flags)
 
 	xhv->xhv_keys++; /* HvTOTALKEYS(hv)++ */
 	if (!next) {			/* initial entry? */
-	} else if (xhv->xhv_keys > xhv->xhv_max /* HvKEYS(hv) > HvMAX(hv) */) {
-		hsplit(PL_strtab);
+	} else if ( SHOULD_DO_HSPLIT(xhv) ) {
+            hsplit(PL_strtab);
 	}
     }
 
diff --git a/t/op/hash.t b/t/op/hash.t
index 278bea7..201260a 100644
--- t/op/hash.t~
+++ t/op/hash.t
@@ -39,22 +39,36 @@ use constant THRESHOLD => 14;
 use constant START     => "a";
 
 # some initial hash data
-my %h2 = map {$_ => 1} 'a'..'cc';
+my %h2;
+my $counter= "a";
+$h2{$counter++}++ while $counter ne 'cd';
 
 ok (!Internals::HvREHASH(%h2), 
     "starting with pre-populated non-pathological hash (rehash flag if off)");
 
 my @keys = get_keys(\%h2);
+my $buckets= buckets(\%h2);
 $h2{$_}++ for @keys;
+$h2{$counter++}++ while buckets(\%h2) == $buckets; # force a split
 ok (Internals::HvREHASH(%h2), 
-    scalar(@keys) . " colliding into the same bucket keys are triggering rehash");
+    scalar(@keys) . " colliding into the same bucket keys are triggering rehash after split");
+
+# returns the number of buckets in a hash
+sub buckets {
+    my $hr = shift;
+    my $keys_buckets= scalar(%$hr);
+    if ($keys_buckets=~m!/([0-9]+)\z!) {
+        return 0+$1;
+    } else {
+        return 8;
+    }
+}
 
 sub get_keys {
     my $hr = shift;
 
     # the minimum of bits required to mount the attack on a hash
     my $min_bits = log(THRESHOLD)/log(2);
-
     # if the hash has already been populated with a significant amount
     # of entries the number of mask bits can be higher
     my $keys = scalar keys %$hr;
END

  # "
  if ($vers =~ /^5\.8\.[2345678]$/) {
    $patch =~ s{diff --git a/ext/Hash-Util-FieldHash.+diff --git a/hv.c b/hv.c}
               {diff --git a/hv.c b/hv.c}gm;
  }
  _patch($patch); #TODO 5.10, 5.12
  _add_patchlevel($vers, "CVE-2013-1667 hsplit rehash");
}

1;
