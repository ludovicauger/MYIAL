SUBROUTINE STEPO(YDGEOMETRY,YDFIELDS,YDMTRAJ,YDMODEL,CDCONF,YDJOT,YDVARBC,YDTCV5,YDGOM5,YDODB,YDFPOS,YDFPDATA)

!**** *STEPO*  - Controls integration job at lowest level

!     Purpose.
!     --------
!        CONTROLS THE INTEGRATION

!**   Interface.
!     ----------
!        *CALL* *STEPO(CDCONF)

!        Explicit arguments :
!        --------------------
!     CHARACTER*9 CDCONF           (in)
!   1   : configuration of IOPACK        IO handling
!   2+3 : configuration of (E)TRANSINVH  inverse transforms
!   4   : configuration of SCAN2M        grid point computations   (under SCAN2M*)
!   6   : configuration of OBS           comparison to observations(under SCAN2M*)
!   7   : configuration of ECOUPL1       coupling for LAM models
!   8   : configuration of (E)TRANSDIRH  direct transforms
!   9   : configuration of (E)SPC..      spectral space computations

!        Implicit arguments :
!        --------------------
!        None

!     Method.
!     -------
!        See documentation

!     Externals.    see includes below.
!     ----------

!     Reference.
!     ----------
!        ECMWF Research Department documentation of the IFS

!     Author.
!     -------
!      Mats Hamrud and Philippe Courtier  *ECMWF*
!      Original : 87-10-15

! Modifications
! -------------
!   11-Jan-2008 Y.Seity Remove call to aro_surf_diagh for surfex 
!                      (replaced by CDCONF(1:1)='S'in iopack)
!   13-Jan-2009 F. Vana   remove useless LSPC_FROM_DI key
!   K. Yessad (Nov 2009): prune lpc_old.
!   K. Yessad (Sep 2010): organigramme simplification.
!   K. Yessad (Jan 2011): new architecture for LBC modules and set-up.
!   R. El Khatib 27-02-2011 Prepare for automatic alloc of arrays needed for spectral nudging
!   L. Magnusson 12-07-13: Option added to call relaxation
!   K. Yessad (Dec 2011): various contributions.
!   R. El Khatib : 01-Mar-2012 LFPOS => NFPOS
!   R. El Khatib 17-07-2012 Fullpos move away
!   T. Wilhelmsson and K. Yessad (Oct 2013) Geometry and setup refactoring.
!   F. Vana  28-Nov-2013 : Redesigned trajectory handling
!   Y. Seity 13-02-2014 apply spectral relaxation only at corrector step
!   P. Brousseau (Feb 2014) : IAU
!   K. Yessad (July 2014): Move some variables.
!   F. Vana  05-Mar-2015  Support for single precision
!   A. Geer  27 Jul 2015 More OOPS cleaning: VARBC by argument
!   M. Leutbecher & S.-J. Lock (Jan 2016) Introduced SPP scheme (LSPP)
!   SJ Lock :   Jan-2016   Enabled multiple perturbation patterns for SPPT
!   R. El khatib 22-Feb-2016 NSTEP passed to opdis
!   S Lang : Feb-2016     Change to write out of SPPT and SPP pattern
!   O. Marsden  Aug 2016   Removed explicit spectral argument, replaced by that in fields argument 
!   K. Yessad (June 2017): Introduce NHQE model.
!   SJ Lock  Oct 2017     Options to reduce frequency of SPPT/SPP pattern updates
! End Modifications
!------------------------------------------------------------------------------

USE TYPE_MODEL          , ONLY : MODEL
USE GEOMETRY_MOD        , ONLY : GEOMETRY
USE FIELDS_MOD          , ONLY : FIELDS
USE MTRAJ_MOD           , ONLY : MTRAJ
USE PARKIND1            , ONLY : JPRD, JPIM, JPRB
USE YOMHOOK             , ONLY : LHOOK, DR_HOOK
USE YOMLUN              , ONLY : NULOUT
USE YOMTIM              , ONLY : RSTART, RVSTART, RTIMEF
USE YOMCT0              , ONLY : NCONF, LR2D, LOPDIS, LCANARI, LOBS, LOBSC1, LOBSREF, LELAM ,LNHDYN
USE YOMMP0              , ONLY : NPROC
USE YOMDYNA             , ONLY : LRUBC
USE YOMCT3              , ONLY : NSTEP
USE YOMECTAB            , ONLY : MTSLOTNO
USE YOMVRTL             , ONLY : L131TL, LOBSTL
USE YOMSPSDT            , ONLY : YSPPT_CONFIG, YSPPT
USE SPECTRAL_ARP_MOD    , ONLY : EVOLVE_ARP, SUM_ARPS, SET_SEED_ARP
USE SPECTRAL_FIELDS_MOD , ONLY : SPECTRAL_FIELD, ASSIGNMENT(=), SPECTRAL_NORM
USE SPP_MOD             , ONLY : YSPP_CONFIG, YSPP, KGET_SEED_SPP
USE YOMGRIB             , ONLY : NENSFNB 
USE GRIDPOINT_FIELDS_MIX, ONLY : ASSIGNMENT(=), GRIDPOINT_FIELD, CLIP_GRID, SELF_ADD, SELF_MUL, ALLOCATE_GRID, DEALLOCATE_GRID
USE YEMLBC_INIT         , ONLY : NECRIPL, NECOTL, LESPCPL, LUNBC
USE MPL_MODULE          , ONLY : MPL_ALLREDUCE, MPL_BARRIER
USE JO_TABLE_MOD        , ONLY : JO_TABLE
USE YOMRLX              , ONLY : LRLXG
USE YOMTRAJ             , ONLY : TRAJEC
USE YOMIAU              , ONLY : LIAU     ,NSTARTIAU,NSTOPIAU
USE YOMGPIAU            , ONLY : GPIAUGFL
USE VARBC_CLASS         , ONLY : CLASS_VARBC
USE TOVSCV_MOD          , ONLY : TOVSCV
USE SUPERGOM_CLASS      , ONLY : CLASS_SUPERGOM
USE DBASE_MOD           , ONLY : DBASE
USE FULLPOS             , ONLY : TFPOS, TFPDATA

!      -----------------------------------------------------------

IMPLICIT NONE

TYPE(GEOMETRY)      , INTENT(INOUT) :: YDGEOMETRY  !! INOUT needed for call to IOPACK
TYPE(FIELDS)        , INTENT(INOUT) :: YDFIELDS
TYPE(MTRAJ)         , INTENT(INOUT) :: YDMTRAJ
TYPE(MODEL)         , INTENT(INOUT) :: YDMODEL
CHARACTER(LEN=9)    , INTENT(IN)    :: CDCONF 
TYPE(JO_TABLE)      , INTENT(INOUT), OPTIONAL :: YDJOT
TYPE(CLASS_VARBC)   , INTENT(INOUT), OPTIONAL :: YDVARBC
TYPE(TOVSCV)        , INTENT(IN),    OPTIONAL :: YDTCV5
TYPE(CLASS_SUPERGOM), INTENT(INOUT), OPTIONAL :: YDGOM5
CLASS(DBASE)        , INTENT(INOUT), OPTIONAL :: YDODB
TYPE(TFPOS)         , INTENT(IN), OPTIONAL    :: YDFPOS
TYPE(TFPDATA)       , INTENT(INOUT), OPTIONAL :: YDFPDATA

!      -----------------------------------------------------------
CHARACTER(LEN=1)   :: CLCONF_TRANSDIR
INTEGER(KIND=JPIM) :: ISPEC2, ISPEC2V
INTEGER(KIND=JPIM) :: IJUM, J2D
INTEGER(KIND=JPIM) :: ISEED, ISEEDX, IDXSTEP
INTEGER(KIND=JPIM) :: JKGLO,ICEND,IBL
INTEGER(KIND=JPIM) :: JARP
INTEGER(KIND=JPIM) :: ITMODSPPT,ITMODSPP
INTEGER(KIND=JPIM), DIMENSION(1)  :: IGRIBGP=(/ 101 /)

LOGICAL :: LLCALL_POSDDH
LOGICAL :: LLESPCL      ! do spectral nudging in LAM models
LOGICAL :: LLCPL        ! do coupling in LAM models
LOGICAL :: LLIAU        ! do IAU
LOGICAL :: LL_TST_GPGFL ! do timestepping on grid-point YDFIELDS%YRGFL%GFL
LOGICAL :: LL_DFISTEP
LOGICAL :: LLFPOS

REAL(KIND=JPRD) :: ZCT, ZVT, ZWT
REAL(KIND=JPRB) :: ZJUM
REAL(KIND=JPRB), DIMENSION(YSPPT%YGPSDT(1)%NG2D) :: ZMIN2D, ZMAX2D
REAL(KIND=JPRB) :: ZW0,ZW1

REAL(KIND=JPRB) :: ZHOOK_HANDLE

CHARACTER(LEN=256) :: CTEMP, CGRIB, CPATOUTN, CLLABEL

TYPE (GRIDPOINT_FIELD) :: YLGPAUX, YLGPSPP   !> auxiliary gridpoint fields

!      -----------------------------------------------------------

#include "user_clock.h"

#include "abor1.intfb.h"
#include "ecoupl1.intfb.h"
#include "ecoupl2.intfb.h"
#include "espcm.intfb.h"
#include "etransdirh.intfb.h"
#include "etransinvh.intfb.h"
#include "evolve_spp.intfb.h"
#include "gpiau.intfb.h"
#include "gpnspng.intfb.h"
#include "gridpoint_norm.intfb.h"
#include "iopack.intfb.h"
#include "obsv.intfb.h"
!#include "obsvad.intfb.h"
#include "opdis.intfb.h"
#include "posddh.intfb.h"
#include "scan2m.intfb.h"
#include "setran.intfb.h"
#include "spec2grid.intfb.h"
#include "spcm.intfb.h"
#include "spc2m.intfb.h"
#include "transdirh.intfb.h"
#include "transinvh.intfb.h"
#include "relaxgp.intfb.h"
#include "updobs.intfb.h"
#include "write_grid_grib.intfb.h"
#include "write_spec_grib.intfb.h"
#include "zeroddh.intfb.h"

!      -----------------------------------------------------------
IF (LHOOK) CALL DR_HOOK('STEPO',0,ZHOOK_HANDLE)
ASSOCIATE(YDGFL5=>YDMTRAJ%YRGFL5, YDGMV5=>YDMTRAJ%YRGMV5, YDSPEC=>YDFIELDS%YRSPEC, &
 & YDGFL=>YDFIELDS%YRGFL,YDGMV=>YDFIELDS%YRGMV, &
 & YDSURF=>YDFIELDS%YRSURF, YDDIM=>YDGEOMETRY%YRDIM, YDDIMV=>YDGEOMETRY%YRDIMV, YDGEM=>YDGEOMETRY%YRGEM, &
 & YDMP=>YDGEOMETRY%YRMP, YDLAP=>YDGEOMETRY%YRLAP, &
 & YDDYN=>YDMODEL%YRML_DYN%YRDYN,YDRIP=>YDMODEL%YRML_GCONF%YRRIP,YDLDDH=>YDMODEL%YRML_DIAG%YRLDDH)

ASSOCIATE(NPROMA=>YDDIM%NPROMA, NSPEC2=>YDDIM%NSPEC2, &
 & NFLEVG=>YDDIMV%NFLEVG, &
 & LFINDVSEP=>YDDYN%LFINDVSEP, NCURRENT_ITER=>YDDYN%NCURRENT_ITER, &
 & NSITER=>YDDYN%NSITER, NVSEPC=>YDDYN%NVSEPC, NVSEPL=>YDDYN%NVSEPL, &
 & NGPTOT=>YDGEM%NGPTOT, &
 & GFL=>YDGFL%GFL, &
 & GMV=>YDGMV%GMV, GMVS=>YDGMV%GMVS, &
 & LHDOUFD=>YDLDDH%LHDOUFD, LHDOUFG=>YDLDDH%LHDOUFG, LHDOUFZ=>YDLDDH%LHDOUFZ, &
 & LHDOUP=>YDLDDH%LHDOUP, &
 & NSPEC2V=>YDMP%NSPEC2V, NSPEC2VF=>YDMP%NSPEC2VF, &
 & NSTART=>YDRIP%NSTART, NSTOP=>YDRIP%NSTOP, TSTEP=>YDRIP%TSTEP, &
 & NPATFR_SPPT=>YSPPT_CONFIG%NPATFR, NPATFR_SPP=>YSPP_CONFIG%NPATFR, &
 & SD_VD=>YDSURF%SD_VD, SD_VF=>YDSURF%SD_VF, SD_VV=>YDSURF%SD_VV, &
 & SD_VX=>YDSURF%SD_VX, SD_WS=>YDSURF%SD_WS, SP_CI=>YDSURF%SP_CI, &
 & SP_CL=>YDSURF%SP_CL, SP_RR=>YDSURF%SP_RR, SP_SB=>YDSURF%SP_SB, &
 & SP_SG=>YDSURF%SP_SG, SP_X2=>YDSURF%SP_X2)
!      -----------------------------------------------------------

!*       0.    VARIOUS INITIALIZATION
!              ----------------------

! Timestepping on grid-point GFL is done when both:
! - grid-point calculations are required
! - direct spectral transforms are required
LL_TST_GPGFL=(CDCONF(7:8) /= '00')

CALL USER_CLOCK(PELAPSED_TIME=ZWT,PTOTAL_CP=ZCT,PVECTOR_CP=ZVT)
ZCT=ZCT-RSTART
ZVT=ZVT-RVSTART
ZWT=ZWT-RTIMEF
RSTART=RSTART+ZCT
RVSTART=RVSTART+ZVT
RTIMEF=RTIMEF+ZWT
ZJUM=10._JPRB**(INT(LOG10(REAL(MAX(NSTOP-NSTART,1),JPRB)))+1)
IJUM=NINT(MAX(ZJUM/100._JPRB,1.0_JPRB))
IF(NSTEP-NSTART <= 10.OR.MOD(NSTEP,IJUM) == 0.OR.(NCONF == 1.OR.NCONF == 302))THEN
  WRITE(NULOUT,'('' NSTEP ='',I6,'' STEPO   '',A9)') NSTEP,CDCONF
ENDIF

IF (LOPDIS) THEN
  CALL OPDIS(CDCONF,'STEPO',ZCT,ZVT,ZWT,RSTART,RTIMEF,NSTEP)
ENDIF

!        0.1   Define configurations for coupling LBC in LAM

!IF (LNHDYN) THEN !DEBUG IF LNHDYN
IF (LELAM) THEN
  LLCPL = (YDMODEL%YRML_LBC%LECOBI.AND.NECRIPL == 1.AND..NOT.LRUBC) .AND.((&
   & CDCONF(3:3) == 'A'.OR.CDCONF(3:3) == 'B'.OR.CDCONF(6:6) == '1')) .AND.(&
   & NCONF/100 == 0.OR.NCONF/100 == 2.OR.NCONF == 302.OR.&
   & NCONF/100 == 7.OR.NCONF == 801.OR.((&
   & NCONF/100==1).AND.(NSTOP>0)).OR.(&
   & NECOTL < 0.AND.(NCONF == 401.OR.NCONF == 501.OR.NCONF == 601)) )  
ELSE
  LLCPL=.FALSE.
ENDIF

IF (CDCONF(7:7)=='D') THEN
  LL_DFISTEP=.TRUE.
ELSE
  LL_DFISTEP=.FALSE.
ENDIF

!     ------------------------------------------------------------------

!*       1.    IO (TRAJECTORY,POST-PROC.,RESTART)
!              ----------------------------------



IF(CDCONF(1:1) /= '0')THEN
!IF (.NOT.LNHDYN) THEN
!LNHDYN=.TRUE.
IF (LNHDYN)  CALL IOPACK(YDGEOMETRY,YDFIELDS,YDGFL5,YDMODEL,CDCONF(1:1))
!LNHDYN=.FALSE.
!ENDIF
ENDIF

!     ------------------------------------------------------------------

!*       2.    INVERSE TRANSFORMS.
!              -------------------

!IF (LNHDYN) THEN !DEBUG IF LNHDYN
IF(CDCONF(2:2) /= '0') THEN
  IF (LELAM) THEN
    CALL ETRANSINVH(YDGEOMETRY,YDFIELDS%YRGFL,YDFIELDS%YRGMV,YDMODEL%YRML_DIAG,YDMODEL%YRML_GCONF,CDCONF, YDSPEC,YDMTRAJ)
  ELSE
    LLFPOS=PRESENT(YDFPOS).AND.PRESENT(YDFPDATA)
    CALL TRANSINVH(YDGEOMETRY,YDFIELDS%YRGFL,YDFIELDS%YRGMV,YDMODEL%YRML_DIAG,YDMODEL%YRML_GCONF, &
 &                 YDMODEL%YRML_DYN%YRDYN%LRFRIC,YDMODEL%YRML_DYN%YRDYN%RKRF,CDCONF,YDSPEC,YDMTRAJ=YDMTRAJ,LDFPOS=LLFPOS)
  ENDIF
  
!IF (LNHDYN) THEN !DEBUG IF LNHDYN
  !--------
  ! Relaxation
  IF (LRLXG .AND. NSTEP > 1) THEN
    CALL RELAXGP(YDGEOMETRY,YDGFL,YDGMV,YDMODEL%YRML_GCONF%YGFL,YDSPEC)
  ENDIF  

  IF (YSPPT_CONFIG%LSPSDT.AND.(CDCONF(2:2)=='A')) THEN
    !
    ITMODSPPT=MOD(NSTEP,NPATFR_SPPT)
    IF (NPATFR_SPPT>1) THEN
      CALL ALLOCATE_GRID(YDGEOMETRY, YLGPAUX, 0, 1, IGRIBGP)
    ENDIF
    DO J2D=1,YSPPT%N2D
      IF (NPATFR_SPPT==1) THEN  !Pattern evolves every timestep
        CALL SUM_ARPS(  YSPPT%YSPSDT_AR1(J2D) )
        WRITE(NULOUT,'(''  SPECTRAL NORMS: Pattern '',I2)') J2D
        WRITE(CTEMP,"(A,I3,A)") "STEPO, YSPSDT_AR1     (",J2D, ",...), "
        CALL SPECTRAL_NORM(YSPPT%YSPSDT_AR1(J2D)%SF,   TRIM(CTEMP))
        CALL SPECTRAL_NORM(YSPPT%YSPSDT_AR1(J2D)%SFSUM,'STEPO, YSPSDT_AR1     (SUM,...),')
        CALL SPEC2GRID(YDGEOMETRY, YSPPT%YSPSDT_AR1(J2D)%SFSUM, YSPPT%YGPSDT(J2D) )
      ELSE
        IF (NSTEP==NSTART.OR.ITMODSPPT==1) THEN  !Initial pattern state/First timestep between pattern updates (NPATFR_SPPT>1)
          CALL SUM_ARPS(  YSPPT%YSPSDT_AR1(J2D) )
          WRITE(NULOUT,'(''  SPECTRAL NORMS: Pattern '',I2)') J2D
          WRITE(CTEMP,"(A,I3,A)") "STEPO, YSPSDT_AR1     (",J2D, ",...), "
          CALL SPECTRAL_NORM(YSPPT%YSPSDT_AR1(J2D)%SF,   TRIM(CTEMP))
          CALL SPECTRAL_NORM(YSPPT%YSPSDT_AR1(J2D)%SFSUM,'STEPO, YSPSDT_AR1     (SUM,...),')
          IF (NSTEP>NSTART) THEN
            YSPPT%YGPSDT0(J2D) = YSPPT%YGPSDT1(J2D)   !NPATFR_SPPT>1: shift time-levels for patterns
          ENDIF
          CALL SPEC2GRID(YDGEOMETRY, YSPPT%YSPSDT_AR1(J2D)%SFSUM, YSPPT%YGPSDT1(J2D) )
        ENDIF
        !
        ! Linear interpolation between YSPPT%YGPSDT0(J2D) and YSPPT%YGPSDT1(J2D) 
        !
        IF (ITMODSPPT==0) THEN  ! NPATFR_SPPT>1: 
          ZW1=1._JPRB
          YSPPT%YGPSDT(J2D) = YSPPT%YGPSDT1(J2D)
        ELSE
          ZW1=REAL(ITMODSPPT,KIND=JPRB)/REAL(NPATFR_SPPT,KIND=JPRB)
          ZW0=1._JPRB - ZW1
          YLGPAUX=YSPPT%YGPSDT0(J2D)
          CALL SELF_MUL(YLGPAUX, ZW0)
          YSPPT%YGPSDT(J2D)=YSPPT%YGPSDT1(J2D)
          CALL SELF_MUL(YSPPT%YGPSDT(J2D), ZW1)
          CALL SELF_ADD(YSPPT%YGPSDT(J2D), YLGPAUX )
        ENDIF
        WRITE(NULOUT,'(''YSPPT%YGPSDT LIN-INTERP, NSTEP ='',I6,''; ZW1 = '',F12.5)') NSTEP, ZW1
      ENDIF ! NPATFR_SPPT==1
      WRITE(CTEMP,"(A,I3,A)") "STEPO, YGPSDT         (",J2D, ",...), "
      CALL GRIDPOINT_NORM(YDGEOMETRY, YSPPT%YGPSDT(J2D),TRIM(CTEMP))
      !
      !    clip if required
      IF (YSPPT_CONFIG%LCLIP_GRID_SDT) THEN
        ZMIN2D(:)= -YSPPT_CONFIG%XCLIP_RATIO_SDT(J2D) * YSPPT_CONFIG%SDEVTOT_SDT(J2D)
        ZMAX2D(:)=  YSPPT_CONFIG%XCLIP_RATIO_SDT(J2D) * YSPPT_CONFIG%SDEVTOT_SDT(J2D)
        CALL CLIP_GRID(YSPPT%YGPSDT(J2D), PMIN2D=ZMIN2D, PMAX2D=ZMAX2D)
        WRITE(CTEMP,"(A,I3,A)") "STEPO, YGPSDT[clipped](",J2D, ",...), "
        CALL GRIDPOINT_NORM(YDGEOMETRY, YSPPT%YGPSDT(J2D), TRIM(CTEMP))
      ENDIF
      !
      !    write multiplicative noise
      IF (YSPPT_CONFIG%LWRITE_ARP) THEN
        CALL WRITE_GRID_GRIB(YDGEOMETRY,YDRIP,YSPPT_CONFIG%COPATGP_SDT(J2D),YSPPT%YGPSDT(J2D),CDMODE='a')
      ENDIF
      !
      IF (YSPPT_CONFIG%LWRPATTRUN_SDT.AND.ANY(NSTEP==YSPPT_CONFIG%NSTEP_PATTRUN(1:YSPPT_CONFIG%NWRPATTRUN_SDT))) THEN
        IF (YSPPT_CONFIG%NWRPATTRUN_SDT>1) THEN
          IDXSTEP = MINLOC(ABS(YSPPT_CONFIG%NSTEP_PATTRUN(1:YSPPT_CONFIG%NWRPATTRUN_SDT) - NSTEP),1)
          WRITE(CTEMP, "(I10)") YSPPT_CONFIG%NHOUR_PATTRUN(IDXSTEP)
          CPATOUTN=TRIM(YSPPT_CONFIG%COPATTRUN_SDT(J2D))//TRIM(ADJUSTL(CTEMP))
        ELSE
          CPATOUTN=TRIM(YSPPT_CONFIG%COPATTRUN_SDT(J2D))
        ENDIF
        WRITE(NULOUT,*) TRIM(CPATOUTN)
        CALL WRITE_SPEC_GRIB(YDGEOMETRY,YDRIP,TRIM(CPATOUTN),YSPPT%YSPSDT_AR1(J2D)%SF,CDMODE="w")
      ENDIF
    ENDDO
    !
    IF (NPATFR_SPPT>1) THEN
      CALL DEALLOCATE_GRID(YLGPAUX)
    ENDIF
  ENDIF
  !
  IF (YSPP_CONFIG%LSPP.AND.(CDCONF(2:2)=='A')) THEN
    !
    ITMODSPP=MOD(NSTEP,NPATFR_SPP)
    DO JARP=1,YSPP%N2D
      IF (NPATFR_SPP>1) THEN
        CALL ALLOCATE_GRID(YDGEOMETRY, YLGPSPP, 0, 1, YSPP%IGRIBCODE(JARP))
      ENDIF
      IF (NPATFR_SPP==1) THEN    !Pattern evolves every timestep
        CALL SPECTRAL_NORM(YSPP%SP_ARP(JARP)%SF, 'YSPP%SP_ARP['//TRIM(YSPP%LAB_ARP(JARP)) //']')
        CALL SPEC2GRID(YDGEOMETRY, YSPP%SP_ARP(JARP)%SF, YSPP%GP_ARP(JARP) )
      ELSE
        IF (NSTEP==NSTART.OR.ITMODSPP==1) THEN  !Initial pattern state/First timestep between pattern updates (NPATFR_SPP>1)
          CALL SPECTRAL_NORM(YSPP%SP_ARP(JARP)%SF, 'YSPP%SP_ARP['//TRIM(YSPP%LAB_ARP(JARP)) //']')
          IF (NSTEP>NSTART) THEN
            YSPP%GP_ARP0(JARP) = YSPP%GP_ARP1(JARP)   !NPATFR_SPP>1: shift time-levels for patterns
          ENDIF
          CALL SPEC2GRID(YDGEOMETRY, YSPP%SP_ARP(JARP)%SF, YSPP%GP_ARP1(JARP) )
        ENDIF
        !
        !
        ! Linear interpolation between YSPP%GP_ARP0(JARP) and YSPP%GP_ARP1(JARP) 
        !
        IF (ITMODSPP==0) THEN  ! (for NPATFR_SPP>1)
          ZW1=1._JPRB
          YSPP%GP_ARP(JARP) = YSPP%GP_ARP1(JARP)
        ELSE
          ZW1=REAL(ITMODSPP,KIND=JPRB)/REAL(NPATFR_SPP,KIND=JPRB)
          ZW0=1._JPRB - ZW1
          YLGPSPP=YSPP%GP_ARP0(JARP)
          CALL SELF_MUL(YLGPSPP, ZW0)                 !ZW0-weighted earlier time-level pattern, YSPP%GP_ARP0(JARP)
          YSPP%GP_ARP(JARP)=YSPP%GP_ARP1(JARP)
          CALL SELF_MUL(YSPP%GP_ARP(JARP), ZW1)       !ZW1-weighted later   time-level pattern, YSPP%GP_ARP1(JARP)
          CALL SELF_ADD(YSPP%GP_ARP(JARP), YLGPSPP )  !linear interpolation between YSPP%GP_ARP0(JARP) and YSPP%GP_ARP1(JARP)
        ENDIF
        WRITE(NULOUT,'(''YSPP%GP_ARP LIN-INTERP, NSTEP ='',I6,''; ZW1 = '',F12.5)') NSTEP, ZW1
      ENDIF  !NPATFR_SPP==1
      !
      CALL GRIDPOINT_NORM(YDGEOMETRY, YSPP%GP_ARP(JARP), 'YSPP%GP_ARP['// TRIM(YSPP%LAB_ARP(JARP)) //']')
    ENDDO
    IF (NPATFR_SPP>1) THEN
      CALL DEALLOCATE_GRID(YLGPSPP)
    ENDIF
    !
    IF (YSPP_CONFIG%LWRPATTRUN.AND.ANY(NSTEP==YSPP_CONFIG%NSTEP_PATTRUN(1:YSPP_CONFIG%NWRPATTRUN))) THEN
      DO JARP=1,YSPP%N2D
        WRITE(CGRIB, "(I10)") YSPP%IGRIBCODE(JARP)
        IF (YSPP_CONFIG%NWRPATTRUN>1) THEN
          IDXSTEP = MINLOC(ABS(YSPP_CONFIG%NSTEP_PATTRUN(1:YSPP_CONFIG%NWRPATTRUN) - NSTEP),1)
          WRITE(CTEMP, "(I10)") YSPP_CONFIG%NHOUR_PATTRUN(IDXSTEP)
          CPATOUTN=TRIM(YSPP_CONFIG%SPP_WRPATTRUN)//TRIM(ADJUSTL(CTEMP))//'_'//TRIM(ADJUSTL(CGRIB))
        ELSE
          CPATOUTN=TRIM(YSPP_CONFIG%SPP_WRPATTRUN)//'_'//TRIM(ADJUSTL(CGRIB))
        ENDIF
        WRITE(NULOUT,*) TRIM(CPATOUTN)
        CALL WRITE_SPEC_GRIB(YDGEOMETRY,YDRIP,TRIM(CPATOUTN),YSPP%SP_ARP(JARP)%SF,CDMODE="w")
      ENDDO
    ENDIF
  ENDIF
ENDIF

!     ------------------------------------------------------------------

!*       3.   GRIDPOINT COMPUTATIONS.
!             -----------------------
!DEBUG BYPASS IN NH
!IF (.NOT.LNHDYN) THEN
IF(CDCONF(3:8) /= '000000') THEN

  IF (NCONF == 1.OR.NCONF==302) THEN
    IF (LHDOUFG.OR.LHDOUFZ.OR.LHDOUFD.OR.LHDOUP) THEN
      CALL ZERODDH(YDDIMV,YDMODEL%YRML_DIAG)
    ENDIF
  ENDIF
  CALL SCAN2M(YDGEOMETRY,YDFIELDS,YDGMV5,YDMODEL,CDCONF,LL_TST_GPGFL,LL_DFISTEP,YDSPEC,TRAJEC(NSTEP),YDGOM5=YDGOM5, &
   & YDFPOS=YDFPOS,YDFPDATA=YDFPDATA, YDODB=YDODB)
  IF (NPROC > 1.AND.LFINDVSEP) THEN
    CALL GSTATS(521,0)
    CALL MPL_ALLREDUCE(NVSEPC,'MAX',CDSTRING='STEPO:')
    CALL MPL_ALLREDUCE(NVSEPL,'MAX',CDSTRING='STEPO:')
    CALL GSTATS(521,1)
  ENDIF

ENDIF
!ENDIF

!     ------------------------------------------------------------------

!*       4.    JO COMPUTATION
!              --------------

IF(LOBS.AND.(CDCONF(6:6) == 'C'.OR.CDCONF(6:6) == 'V')&
   & .AND..NOT.(LOBSREF.AND.L131TL.AND.LOBSTL)&
   & .AND..NOT.((LOBSC1.OR.((NCONF == 131).AND.(LOBSREF))))) THEN  
  IF(.NOT.PRESENT(YDVARBC)) CALL ABOR1('STEPO : YDVARBC MISSING')
  ! Decide on whether to do direct and/or adjoint Jo computations
  IF (LCANARI) THEN
    CALL OBSV(YDMODEL%YRML_PHY_EC%YREPHY,YDMODEL%YRML_PHY_MF,YDJOT,YDVARBC,YDTCV5,YDGOM5,YDODB,MTSLOTNO,'DI')
  ELSEIF (LOBSC1.OR.((NCONF == 131).AND.(LOBSREF))) THEN
    CALL OBSV(YDMODEL%YRML_PHY_EC%YREPHY,YDMODEL%YRML_PHY_MF,YDJOT,YDVARBC,YDTCV5,YDGOM5,YDODB,MTSLOTNO,'DI')
  ELSEIF ((NCONF == 131).AND..NOT.LOBSREF) THEN
    IF (L131TL) THEN
      CALL ABOR1('AJGDB: To reinstate this option, please pass in YDGOM by argument')
    ELSE
      IF (.NOT.LOBSTL) THEN
        CALL OBSV(YDMODEL%YRML_PHY_EC%YREPHY,YDMODEL%YRML_PHY_MF,YDJOT,YDVARBC,YDTCV5,YDGOM5,YDODB,MTSLOTNO,'DA')
      ELSE
        CALL ABOR1('STEPO ERROR : TL OBS OPER NEEDS TL MODEL')
      ENDIF
    ENDIF
  ELSE
    CALL ABOR1('STEPO ERROR : UNKNOWN WAY TO USE OBSERVATIONS')
  ENDIF

  IF(.NOT.LCANARI) THEN
    CALL UPDOBS(YDRIP)
  ENDIF
ENDIF

!     ------------------------------------------------------------------

!*       5.    DIAGNOSTICS.
!              ------------

LLCALL_POSDDH=(NCONF == 1.OR.NCONF == 302)&
& .AND.(CDCONF(4:4) /= '0').AND.(CDCONF(4:4) /= 'X')&
& .AND.(LHDOUFG.OR.LHDOUFZ.OR.LHDOUFD.OR.LHDOUP)&
& .AND.(NCURRENT_ITER == 0)
IF (LLCALL_POSDDH) THEN
  CALL GSTATS(799,0)
  CALL MPL_BARRIER(CDSTRING='STEPO:')
  CALL GSTATS(799,1)
  CALL GSTATS(31,0)
  CALL POSDDH(YDDIMV,YDSURF,YDMODEL%YRML_DIAG,YDMODEL%YRML_PHY_G%YRDPHY,YDMODEL%YRML_GCONF,YDMODEL%YRML_PHY_MF%YRPHY)
  CALL GSTATS(31,1)
ENDIF

!     ------------------------------------------------------------------

!*       8.    DIRECT TRANSFORMS.
!              ------------------

!ENDIF !DEBUG END IF LNHDYN AFTER HERE IT IS OK
IF(CDCONF(7:8) /= '00')THEN
  CLCONF_TRANSDIR=CDCONF(8:8)
  IF (LLCPL) THEN
    CALL ECOUPL1(YDGEOMETRY,YDMODEL,YDFIELDS,LL_DFISTEP)
    IF(LUNBC) CALL ECOUPL2(YDGEOMETRY,YDMODEL,YDFIELDS,LL_DFISTEP)
  ENDIF
  IF (LELAM) THEN
    CALL ETRANSDIRH(YDGEOMETRY,YDFIELDS%YRGFL,YDFIELDS%YRGMV,CLCONF_TRANSDIR, YDMODEL%YRML_GCONF%YRDIMF%NFTHER, YDSPEC)
  ELSE
    CALL TRANSDIRH(YDGEOMETRY,YDFIELDS%YRGFL,YDFIELDS%YRGMV,CLCONF_TRANSDIR,YDMODEL%YRML_GCONF%YRDIMF%NFTHER,YDSPEC)
  ENDIF
ENDIF

!     ------------------------------------------------------------------

!*       9.    SPECTRAL COMPUTATIONS.
!              ----------------------

!ENDIF !DEBUG END IF LNHDYN AFTER HERE IT IS OK
IF (CDCONF(9:9) /= '0') THEN
  LLIAU=LIAU.AND.(NSTEP>=NSTARTIAU).AND.(NSTEP<=NSTOPIAU).AND.(NCURRENT_ITER==NSITER)
  !*    standard spectral computations
  IF (LELAM) THEN
    IF (LR2D) THEN
      CALL ABOR1('STEPO : ESPC2M DOES NOT EXIST')
    ELSE
      LLESPCL=LESPCPL.AND.MOD(NSTEP,YDMODEL%YRML_LBC%NEFRSPCPL)==0.AND.NCURRENT_ITER==NSITER
      IF (LLESPCL) THEN
        ISPEC2=NSPEC2
        ISPEC2V=MAX(NSPEC2V,NSPEC2VF)
      ELSE
        ISPEC2=0
        ISPEC2V=0
      ENDIF
      CALL ESPCM(YDGEOMETRY,YDMODEL,YDFIELDS,CDCONF(9:9),LLESPCL,LLIAU,ISPEC2,ISPEC2V)
    ENDIF
  ELSE
    IF (LR2D) THEN
      CALL SPC2M(YDGEOMETRY,YDRIP,YDDYN,CDCONF(9:9),YDSPEC)
    ELSE
      CALL SPCM(YDGEOMETRY,YDMODEL,CDCONF(9:9),YDSPEC,YDGMV)
    ENDIF
  ENDIF

 ! IAU only coded for LAM case 
  IF (LLIAU) THEN
!$OMP PARALLEL DO SCHEDULE(DYNAMIC,1) PRIVATE(JKGLO,ICEND,IBL)
    DO JKGLO=1,NGPTOT,NPROMA
      IBL=(JKGLO-1)/NPROMA+1
      ICEND=MIN(NPROMA,NGPTOT-JKGLO+1)
      CALL GPIAU(YDMODEL%YRML_GCONF%YGFL,NPROMA,NFLEVG,1,ICEND,GFL(:,:,:,IBL),GPIAUGFL(:,:,1,IBL))
    ENDDO
!$OMP END PARALLEL DO
  ENDIF

  ! new sponge for 2D and 3D models (grid-point GFL only).
  ! in all cases must be done after "scan2m" transfer GFL=GFLT1.
  ! for coupled fields in LAM models must be done after coupling.
  IF (YDMODEL%YRML_DYN%YRSPNG%LNSPONGE) THEN
!$OMP PARALLEL DO SCHEDULE(DYNAMIC,1) PRIVATE(JKGLO,ICEND,IBL)
    DO JKGLO=1,NGPTOT,NPROMA
      IBL=(JKGLO-1)/NPROMA+1
      ICEND=MIN(NPROMA,NGPTOT-JKGLO+1)
      CALL GPNSPNG(YDMODEL%YRML_GCONF%YGFL,YDMODEL%YRML_DYN%YRSPNG,NPROMA,NFLEVG,1,ICEND,GFL(:,:,:,IBL))
    ENDDO
!$OMP END PARALLEL DO
  ENDIF

  IF (YSPPT_CONFIG%LSPSDT.AND.CDCONF(9:9) == 'A') THEN
    !
    DO J2D=1,YSPPT%N2D
      IF (YSPPT_CONFIG%LRESETSEED_SDT.AND.MOD(NSTEP,YSPPT_CONFIG%RESETSEEDFRQ_SDT)==0) THEN
        IF (YSPPT_CONFIG%LABSTIMSEED_SDT) THEN
          ISEEDX=YSPPT%NSEED_SDT(J2D)
        ELSE
          ISEEDX=YSPPT%NSEED_SDT(J2D)+NSTEP*256
        ENDIF
        IF (YSPPT_CONFIG%LUSESETRAN_SDT) THEN
          CALL SETRAN( ISEEDX, KOUTSEED=ISEED, LABSTIME=YSPPT_CONFIG%LABSTIMSEED_SDT,PTSTEP=TSTEP)
        ELSE
          ISEED=ISEEDX
        ENDIF
        WRITE(NULOUT,'(''  STEPO: Using seed '',I15,'' to evolve YSPSDT_AR1('',I3,'') in NSTEP='',I12)')  ISEED, J2D, NSTEP
        CALL SET_SEED_ARP(YSPPT%YSPSDT_AR1(J2D), ISEED)
      ENDIF
      !
      IF (ITMODSPPT==0) THEN  ! MOD(NSTEP,NPATFR_SPPT)==0
        WRITE(NULOUT,'(''  STEPO: evolving YSPSDT_AR1('',I3,'')'')') J2D
        CALL EVOLVE_ARP(YSPPT%YSPSDT_AR1(J2D))
      ENDIF
      !
      IF (YSPPT_CONFIG%LWRITE_ARP) THEN
        CALL WRITE_SPEC_GRIB(YDGEOMETRY,YDRIP,YSPPT_CONFIG%COPATSP_SDT(J2D),YSPPT%YSPSDT_AR1(J2D)%SF,CDMODE='a')
      ENDIF
    ENDDO
  ENDIF !LSPSDT
  IF (YSPP_CONFIG%LSPP.AND.CDCONF(9:9) == 'A') THEN
    IF (YSPP_CONFIG%LRESETSEED.AND.MOD(NSTEP,YSPP_CONFIG%RESETSEEDFRQ)==0) THEN
      DO JARP=1,YSPP%N2D
        CLLABEL=YSPP%LAB_ARP(JARP)
        ISEED= KGET_SEED_SPP(YSPP_CONFIG, CLLABEL, KMEMBER=NENSFNB, KSHIFT=YSPP_CONFIG%SHIFTSEED, &
             & LABSTIME=YSPP_CONFIG%LABSTIMSEED, LDVERBOSE=.TRUE., PTSTEP=TSTEP)
        WRITE(NULOUT,'(''   pattern '',I3,'' for '',A16,'' using seed '',I12)')  JARP,YSPP%LAB_ARP(JARP),ISEED 
        CALL SET_SEED_ARP(YSPP%SP_ARP(JARP), ISEED)
      ENDDO
    ENDIF
    !
    IF (ITMODSPP==0) THEN  ! MOD(NSTEP,NPATFR_SPP)==0
      WRITE(NULOUT,'(''  STEPO: evolving YSPP'')')
      CALL EVOLVE_SPP(YSPP)
    ENDIF
  ENDIF
ENDIF

!     ------------------------------------------------------------------

END ASSOCIATE
END ASSOCIATE
IF (LHOOK) CALL DR_HOOK('STEPO',1,ZHOOK_HANDLE)
END SUBROUTINE STEPO
