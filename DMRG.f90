!INCLUDE 'MATHIO.F90'
!INCLUDE 'TENSOR.F90'
! ############### CONST ###################
MODULE CONST
	COMPLEX, PARAMETER :: Z0 = (0.,0.), Z1 = (1.,0.), ZI = (0.,1.)
	REAL, PARAMETER :: PI = 4*ATAN(1.)
END MODULE CONST
! ############### MODEL ###################
MODULE MODEL
	USE CONST
!	REAL    :: BETA = 0.440687
	REAL    :: BETA = 1.
	REAL    :: THETA = 0.*PI
	INTEGER :: LEN = 8 ! must be even and larger than 4
	INTEGER :: MAX_CUT = 8
	REAL    :: MAX_ERR = 0.
END MODULE MODEL
! ############## PHYSICS ###################
MODULE PHYSICS
	USE TENSORIAL
CONTAINS
! ------------ set MPO tensor ---------------
! square lattice MPO
SUBROUTINE SET_MPO(T)
	USE MODEL
	TYPE(TENSOR), INTENT(OUT) :: T ! MPO tensor output
	! local variables
	TYPE(TENSOR) :: X, Y, U, S
	COMPLEX, ALLOCATABLE :: A(:,:)
	COMPLEX :: Q, B
	
! ++++++++ set the vertex tensor here ++++++++
	Q = THETA * ZI
	B = BETA * Z1
	X =  TENSOR([2,2,2,2],[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],[EXP(2*B),EXP(Q/4.),EXP(Q/4.),EXP(Z0),EXP(Q/4.),EXP(-2*B - Q/2.),EXP(Z0),EXP(-Q/4.),EXP(Q/4.),EXP(Z0),EXP(-2*B + Q/2.),EXP(-Q/4.),EXP(Z0),EXP(-Q/4.),EXP(-Q/4.),EXP(2*B)])
! ++++++++++++++++++++++++++++++++++++++++++++
	! symm SVD of X to unitary U and diagonal S
	CALL SYSVD(X,[1,4],[3,2],U,S)
	S%VALS = SQRT(S%VALS) ! split S to half
	U = TEN_PROD(U,S,[3],[1]) ! attach the half S to U
	! set Y tensor
	Y = EYE_TEN([2,2,2])
	! contract U from both sides with Y
	U = TEN_PROD(Y,U,[1],[2])
	T = TEN_PROD(U,U,[1,3],[3,1])
!	T%VALS = T%VALS/2/EXP(ABS(BETA))
END SUBROUTINE SET_MPO
! ----------- DMRG -----------
! DMRG Kernel
SUBROUTINE DMRG(T, A, B, S)
! input: T - MPO site tensor
! output: A,B - MPS tensor, S - entanglement matrix
	USE MODEL
	TYPE(TENSOR), INTENT(IN)  :: T
	TYPE(TENSOR), INTENT(OUT) :: A(LEN), B(LEN), S
	! local tensor
	TYPE(TENSOR) :: TA(LEN), TB(LEN), S0, TS, W
	! local variables
	INTEGER :: DPHY, L
	COMPLEX :: TVAL
	
	! check validity of system size LEN
	IF (MODULO(LEN,2) == 1 .OR. LEN <= 4) THEN
		WRITE (*,'(A)') 'DMRG::xlen: LEN must be even and greater than 4.'
		STOP
	END IF
	! initialize tensors
	! boundary MPO
	TA(1) = T
	TB(1) = T
	! boundary MPS
	DPHY = T%DIMS(1) ! get physical dim
	A(1) = TEN_PROD(TENSOR([1],[0],[Z1]),EYE_TEN([DPHY,DPHY]))
	B(1) = A(1)
	! initial entanglement mat
	S0 = EYE_TEN([1,1])
	S  = EYE_TEN([DPHY,DPHY],SQRT(Z1/DPHY))
	! inf-size DMRG (warm up)
	DO L = 2, LEN/2
		! estimate trial W
		S0%VALS = Z1/S0%VALS ! cal S0^(-1) -> S0
		W = MAKE_W5(A(L-1), B(L-1), S, S0)
		S0 = S ! S0 is used, update to S
		TS = GET_TS(T, TA(L-1), TB(L-1)) ! construct TS
		TVAL = ANNEAL(TS, W) ! anneal W by TS
		! SVD split W, and update A, B, S
		CALL SVD(W,[1,2],[3,4],A(L),B(L),S,MAX_CUT,MAX_ERR)
		! update TA, TB
		TA(L) = GET_TX(TA(L-1), T, A(L))
		TB(L) = GET_TX(TB(L-1), T, B(L))
		WRITE (*,'(I3,A,G10.4,A,G10.4,A,100F6.3)') L, ': (', REALPART(TVAL),',', IMAGPART(TVAL), ') S:', REALPART(S%VALS)
	END DO
	! finite-size DMRG (first sweep)
	DO L = LEN/2+1, LEN-2
		! estimate trial W
		W = MAKE_W3(S, B(LEN-L+1), B(LEN-L))
		TS = GET_TS(T, TA(L-1), TB(LEN-L-1)) ! construct TS
		TVAL = ANNEAL(TS, W) ! anneal W by TS
		! SVD split W, update A, S
		CALL SVD(W,[1,2],[3,4],A(L),B(LEN-L),S,MAX_CUT,MAX_ERR)
		! update TA
		TA(L) = GET_TX(TA(L-1), T, A(L))
		WRITE (*,'(I3,A,G10.4,A,G10.4,A,100F6.3)') L, ': (', REALPART(TVAL),',', IMAGPART(TVAL), ') S:', REALPART(S%VALS)
	END DO
	! finite-size DMRG (backward sweep)
	DO L = 3, LEN-2
		! estimate trial W
		W = MAKE_W3(S, A(LEN-L+1), A(LEN-L))
		TS = GET_TS(T, TB(L-1), TA(LEN-L-1)) ! construct TS
		TVAL = ANNEAL(TS, W) ! anneal W by TS
		! SVD split W, update B, S
		CALL SVD(W,[1,2],[3,4],B(L),A(LEN-L),S,MAX_CUT,MAX_ERR)
		! update TB
		TB(L) = GET_TX(TB(L-1), T, B(L))
		WRITE (*,'(I3,A,G10.4,A,G10.4,A,100F6.3)') LEN-L+1, ': (', REALPART(TVAL),',', IMAGPART(TVAL), ') S:', REALPART(S%VALS)
	END DO
	! finite-size DMRG (forward sweep)
	DO L = 3, LEN-2
		! estimate trial W
		W = MAKE_W3(S, B(LEN-L+1), B(LEN-L))
		TS = GET_TS(T, TA(L-1), TB(LEN-L-1)) ! construct TS
		TVAL = ANNEAL(TS, W) ! anneal W by TS
		! SVD split W, update A, S
		CALL SVD(W,[1,2],[3,4],A(L),B(LEN-L),S,MAX_CUT,MAX_ERR)
		! update TA
		TA(L) = GET_TX(TA(L-1), T, A(L))
		WRITE (*,'(I3,A,G10.4,A,G10.4,A,100F6.3)') L, ': (', REALPART(TVAL),',', IMAGPART(TVAL), ') S:', REALPART(S%VALS)
	END DO
END SUBROUTINE DMRG
! estimate 2-site trial state
FUNCTION MAKE_W5(A, B, S, SI) RESULT(W)
	TYPE(TENSOR), INTENT(IN) :: A, B, S, SI
	TYPE(TENSOR) :: W
	
	W = TEN_PROD(TEN_PROD(TEN_PROD(S,B,[2],[3]),SI,[2],[1]),TEN_PROD(S,A,[2],[3]),[3],[2])
END FUNCTION MAKE_W5
! estimate 1-site trial state
FUNCTION MAKE_W3(S, X1, X2) RESULT(W)
	TYPE(TENSOR), INTENT(IN) :: S, X1, X2
	TYPE(TENSOR) :: W
	
	W = TEN_PROD(TEN_PROD(S,X1,[2],[3]),X2,[2],[3])
END FUNCTION MAKE_W3
! construct 2-block-2-site system tensor
FUNCTION GET_TS(T, TA, TB) RESULT (TS)
	TYPE(TENSOR), INTENT(IN) :: T, TA, TB
	TYPE(TENSOR) :: TS
	
	TS = TEN_PROD(TEN_PROD(TA,T,[4],[2]),TEN_PROD(TB,T,[4],[2]),[2,6],[2,6])
END FUNCTION GET_TS
! anneal the state W to fix point of TS
FUNCTION ANNEAL(TS, W) RESULT (TVAL)
! input: TS - system transfer tensor, W - state
! on output: W  is modified to the fixed point state
!	USE MATHIO
	USE CONST
	TYPE(TENSOR), INTENT(IN) :: TS
	TYPE(TENSOR), INTENT(INOUT) :: W
	COMPLEX :: TVAL
	! parameters
	INTEGER, PARAMETER :: N = 16 ! Krylov space dimension
	INTEGER, PARAMETER :: MAX_ITER = 50 ! max interation
	REAL, PARAMETER :: TOL = 1.E-12 ! allowed error of Tval
	! local variables
	INTEGER :: DIM, I, J, K, ITER, INFO
	INTEGER, ALLOCATABLE :: LINDS(:), RINDS(:), WINDS(:)
	COMPLEX, ALLOCATABLE :: Q(:,:)
	COMPLEX :: TVAL0, H(N,N), E(N),VL(0,0),VR(N,N),WORK(65*N)
	REAL :: RWORK(2*N)
	LOGICAL :: EXH
	
	! unpack data from tensor
	! collect leg-combined inds in TS and W
	LINDS = COLLECT_INDS(TS,[1,3,5,7])
	RINDS = COLLECT_INDS(TS,[2,4,6,8])
	WINDS = COLLECT_INDS(W,[1,2,3,4])
	! cal total dim of W
	DIM = PRODUCT(W%DIMS)
	! allocate Krylov space
	ALLOCATE(Q(0:DIM-1,N))
	Q = Z0
	FORALL (I = 1:SIZE(W%INDS))
		Q(WINDS(I),1) = W%VALS(I)
	END FORALL
	Q(:,1) = Q(:,1)/SQRT(DOT_PRODUCT(Q(:,1),Q(:,1))) ! normalize
	! prepare to start Arnoldi iteration
	TVAL0 = Z0
	EXH = .FALSE. ! space exhausted flag
	! use Arnoldi iteration algorithm
	DO ITER = 1, MAX_ITER
		H = Z0 ! initialize Heisenberg matrix
		! construct Krylov space
		DO K = 2, N
			! apply TS to Q(:,K-1) -> Q(:,K)
			Q(:,K) = Z0
			DO I = 1,SIZE(TS%INDS)
				Q(LINDS(I),K) = Q(LINDS(I),K) + TS%VALS(I)*Q(RINDS(I),K-1)
			END DO
			! orthogonalization by stabilized Gram–Schmidt process
			DO J = 1, K-1
				H(J,K-1) = DOT_PRODUCT(Q(:,J),Q(:,K))
				Q(:,K) = Q(:,K) - H(J,K-1)*Q(:,J)
			END DO
			! cal the norm of residual vector
			H(K,K-1) = SQRT(DOT_PRODUCT(Q(:,K),Q(:,K)))
			! if it is vanishing, the Arnoldi iteration has broken down
			IF (ABS(H(K,K-1))<TOL) THEN
				EXH = .TRUE.
				EXIT ! exit the iteration, stop construction of Krylov space
			END IF
			! otherwise, normalize the residual vect to a new basis vect
			Q(:,K) = Q(:,K)/H(K,K-1)
		END DO !K
		! now the Heisenberg matrix has been constructed
		! the action of TS is represented on the basis Q as H
		! call LAPACK to diagonalize H
		CALL ZGEEV('N','V',N,H,N,E,VL,1,VR,N,WORK,65*N,RWORK,INFO)
		! now E holds the eigen vals, and VR the eigen vects
		! find the max abs eigen val
		I = MAXLOC(ABS(E),1,IMAG(E)>-TOL/2)
		TVAL = E(I) ! save it in Tval
		! reorganize the eigen vector
		Q(:,1) = MATMUL(Q,VR(:,I)) ! save to 1st col of Q
		Q(:,1) = Q(:,1)/SQRT(DOT_PRODUCT(Q(:,1),Q(:,1))) ! normalize
		! check convergence
		! if space exhausted, or relative error < tol
		IF (EXH .OR. ABS((TVAL-TVAL0)/TVAL) < TOL) THEN
			! Arnoldi iteration has converge
			EXIT ! exit Arnoldi interation
		ELSE ! not converge, next iteration
			TVAL0 = TVAL ! save TVAL to TVAL0
		END IF
	END DO ! next Arnoldi interation
	! if exceed max iteration
	IF (ITER > MAX_ITER) THEN !then power iteration has not converge
		WRITE (*,'(A)') 'ANNEAL::fcov: Arnoldi iteration failed to converge.'
	END IF
	! reconstruct W tensor for output
	W%INDS = [(I,I=0,DIM-1)]
	W%VALS = Q(:,1)
END FUNCTION ANNEAL
! update TX given T and X
FUNCTION GET_TX(TX, T, X) RESULT (TX1)
! input: TX - block tensor, T - site tensor (MPO), X - projector
! return the enlarged block tensor TX1
	TYPE(TENSOR), INTENT(IN) :: TX, T, X
	TYPE(TENSOR) :: TX1
	
	! zipper-order contraction algorithm
	TX1 = TEN_PROD(TEN_PROD(TEN_PROD(TEN_CONJG(X),TX,[1],[1]),X,[4],[1]),T,[1,4,5],[1,2,3])
END FUNCTION GET_TX
! ----------- MEASURE -----------
! correlation of MPS
SUBROUTINE CORR(M,O1,O2)
! input: M - MPS tensor, O1, O2 -  observables
! output:
	TYPE(TENSOR), INTENT(IN) :: M, O1, O2
	! local tensors
	TYPE(TENSOR) :: MC, M0, M1, M2
	
	MC = TEN_CONJG(M)
	M0 = TEN_FLATTEN(TEN_PROD(MC,M,[2],[2]),[1,3,0,2,4])
	M1 = TEN_FLATTEN(TEN_PROD(MC,TEN_PROD(O1,M,[2],[2]),[2],[1]),[1,3,0,2,4])
	M2 = TEN_FLATTEN(TEN_PROD(MC,TEN_PROD(O2,M,[2],[2]),[2],[1]),[1,3,0,2,4])
	CALL TEN_SAVE('M0',M0)
	CALL TEN_SAVE('M1',M1)
	CALL TEN_SAVE('M2',M2)
END SUBROUTINE CORR
! end of module PHYSICS
END MODULE PHYSICS
! ################ TASK ####################
MODULE TASK
	USE PHYSICS
CONTAINS
! ------------ Data --------------
! collect data
! ------------ Tests -------------
! test routine
SUBROUTINE TEST()
	REAL, ALLOCATABLE :: S(:)
	
	S = [2.,2.,2.,2.,2.,1.,1.,1.,0.5,0.5,0.,0.,0.]
	SVD_CUT = 9
	SVD_ERR = 0.
	CALL FIND_DCUT(S, SVD_CUT, SVD_ERR)
	PRINT *, SVD_CUT, SVD_ERR
END SUBROUTINE TEST
! test MPO
SUBROUTINE TEST_MPO()
	TYPE(TENSOR) :: T
	
	CALL SET_MPO(T)
!	CALL TEN_PRINT(T)
	CALL TEN_SAVE('T',TEN_TRANS(T,[2,4,1,3]))
END SUBROUTINE TEST_MPO
! test DMRG
SUBROUTINE TEST_DMRG()
	USE MODEL
	TYPE(TENSOR) :: T, A(LEN), B(LEN), S
	INTEGER :: ITER
	
	CALL SET_MPO(T)
	WRITE (*,'(A,I3,A,F5.2,A,F5.2,A)') 'cut = ', MAX_CUT, ', theta = ', THETA/PI, '*pi, beta = ', BETA
	CALL DMRG(T, A, B, S)
!	CALL CORR(M, PAULI_MAT([3]), PAULI_MAT([3]))
END SUBROUTINE TEST_DMRG
! end of module TASK
END MODULE TASK
! ############### PROGRAM ##################
PROGRAM MAIN
	USE TASK
	INTEGER :: I
	PRINT *, '------------ DMRG -------------'
		
!	CALL TEST()
!	CALL TEST_MPO()
	CALL TEST_DMRG()
END PROGRAM MAIN