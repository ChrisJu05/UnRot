/// Subject profiles: domain knowledge that steers reel generation.
///
/// A profile adds subject-specific instructions to the AI prompt (topics,
/// notation, typical exam tasks), adds math/science reel types to the mix and
/// can be detected automatically from imported text. The built-in profiles
/// target the 3rd semester of Electrical Engineering at TUM (Elektrotechnik
/// und Informationstechnik) plus general maths/physics.
class SubjectProfile {
  const SubjectProfile({
    required this.id,
    required this.name,
    required this.localName,
    required this.guidance,
    this.extraMix = const {},
    this.keywords = const [],
  });

  final String id;
  final String name;

  /// German name, e.g. "Signaltheorie".
  final String localName;

  /// Domain instructions for the AI.
  final String guidance;

  /// Weights added to the study mode's reel mix.
  final Map<String, double> extraMix;

  /// Lower-case keywords used for automatic detection.
  final List<String> keywords;

  String get label => name == localName ? name : '$localName ($name)';
}

class SubjectProfiles {
  static const general = SubjectProfile(id: 'general', name: 'General', localName: 'General', guidance: '');

  static const all = <SubjectProfile>[
    general,
    SubjectProfile(
      id: 'analysis',
      name: 'Analysis / Calculus',
      localName: 'Analysis',
      guidance:
          'Subject: real and complex analysis for engineers (limits, sequences and series with convergence tests, '
          'continuity, differentiation in one and several variables, Taylor expansion, extrema with constraints '
          '(Lagrange multipliers), multiple integrals and coordinate transformations, curve and surface integrals, '
          'integral theorems of Gauss and Stokes, ordinary differential equations, complex functions, Cauchy integral '
          'formula and residue theorem). State theorems (Sätze) precisely with all assumptions (Voraussetzungen), give '
          'recipes (Rechenrezepte) for standard procedures (e.g. finding extrema, solving linear ODEs, computing '
          'residues) and practise them with concrete calculations. Use function plots for limits, Taylor polynomials '
          'and convergence.',
      extraMix: {'theorem': 3, 'math_recipe': 3, 'calc_exercise': 2, 'formula': 1, 'visual': 1},
      keywords: [
        'grenzwert',
        'konvergenz',
        'konvergent',
        'reihe',
        'stetig',
        'differenzierbar',
        'ableitung',
        'integral',
        'taylor',
        'extremum',
        'lagrange',
        'differentialgleichung',
        'holomorph',
        'residuum',
        'limit',
        'convergence',
        'derivative',
        'differentiable',
        'continuous',
        'series',
        'cauchy',
        'jacobi',
        'gradient',
        'hesse',
      ],
    ),
    SubjectProfile(
      id: 'signal_theory',
      name: 'Signal theory / Signals and systems',
      localName: 'Signaltheorie',
      guidance:
          'Subject: signals and systems (Signaltheorie): continuous and discrete-time signals, elementary signals '
          '(δ(t), ε(t)/u(t), rect, si/sinc), LTI systems, impulse response, convolution (Faltung), Fourier series, '
          'Fourier transform and its theorems (shift, modulation, scaling, Parseval), DTFT and DFT, Laplace and '
          'z-transform, transfer function, poles and zeros, stability (BIBO), sampling theorem (Abtasttheorem) and '
          'aliasing, ideal and real filters, modulation basics. Use the course notation x(t), X(f) or X(jω), h(t), '
          'H(s), *, ∘—•. Prefer visuals: signals in time and frequency with sliders (frequency, shift, width), '
          'convolution animations, pole-zero sketches. Give recipes for convolution, partial fractions for inverse '
          'Laplace/z-transforms and stability checks, and formula cards for transform pairs.',
      extraMix: {'visual': 3, 'math_recipe': 2, 'formula': 2, 'calc_exercise': 1.5, 'theorem': 1.5},
      keywords: [
        'fourier',
        'laplace',
        'z-transformation',
        'z-transform',
        'faltung',
        'convolution',
        'impulsantwort',
        'impulse response',
        'übertragungsfunktion',
        'transfer function',
        'lti',
        'abtasttheorem',
        'sampling',
        'aliasing',
        'spektrum',
        'spectrum',
        'dirac',
        'sprungantwort',
        'pol-nullstellen',
        'dft',
        'dtft',
        'filter',
      ],
    ),
    SubjectProfile(
      id: 'stochastic_signals',
      name: 'Stochastic signals / Probability',
      localName: 'Stochastische Signale',
      guidance:
          'Subject: probability and stochastic signals: random variables, PDF/CDF (Dichte, Verteilungsfunktion), '
          'expectation, variance, moments, characteristic function, joint and conditional distributions, Bayes, '
          'independence, correlation and covariance, transformation of random variables, Gaussian and other common '
          'distributions, law of large numbers, central limit theorem, random processes, stationarity (strict/wide '
          'sense), ergodicity, autocorrelation, power spectral density (Leistungsdichtespektrum), Wiener–Khinchin '
          'theorem, LTI systems with random inputs, white noise, Markov chains. Prefer visuals of PDFs/CDFs with '
          'sliders for parameters (μ, σ, λ), formula cards for moments and distributions, theorems with exact '
          'assumptions, and numeric calculation exercises.',
      extraMix: {'theorem': 2, 'formula': 2, 'calc_exercise': 2, 'visual': 2, 'math_recipe': 1.5},
      keywords: [
        'zufallsvariable',
        'random variable',
        'wahrscheinlichkeit',
        'probability',
        'erwartungswert',
        'expectation',
        'varianz',
        'variance',
        'dichte',
        'verteilung',
        'distribution',
        'gauß',
        'gaussian',
        'korrelation',
        'correlation',
        'kovarianz',
        'covariance',
        'stationär',
        'stationary',
        'ergodisch',
        'leistungsdichtespektrum',
        'power spectral density',
        'markov',
        'zufallsprozess',
        'random process',
        'stochastisch',
      ],
    ),
    SubjectProfile(
      id: 'semiconductor_physics',
      name: 'Solid-state and semiconductor device physics',
      localName: 'Festkörper- und Halbleiterbauelemente-Physik',
      guidance:
          'Subject: solid-state physics and semiconductor devices: crystal lattices, band model, effective mass, '
          'density of states, Fermi–Dirac statistics and Fermi level, intrinsic and doped semiconductors, mass action '
          'law n·p = n_i², drift and diffusion currents, mobility, Einstein relation, continuity equation, '
          'generation/recombination and lifetime, pn junction (space charge region, built-in voltage, Shockley '
          'equation, capacitance), bipolar transistor, MOS capacitor and MOSFET (threshold voltage, I–V '
          'characteristics). Use standard constants (q = 1.602·10⁻¹⁹ C, k_B T/q ≈ 25.9 mV at 300 K, n_i(Si) ≈ '
          '10¹⁰ cm⁻³) and the cm-based units common in device physics. Prefer formula cards with symbol legends and '
          'units, numeric calculation exercises with realistic values, band diagrams and I–V curves as visuals.',
      extraMix: {'formula': 3, 'calc_exercise': 3, 'visual': 1.5, 'math_recipe': 1.5, 'theorem': 0.5},
      keywords: [
        'halbleiter',
        'semiconductor',
        'bandlücke',
        'band gap',
        'bandgap',
        'fermi',
        'dotierung',
        'doping',
        'donator',
        'akzeptor',
        'ladungsträger',
        'carrier',
        'beweglichkeit',
        'mobility',
        'diffusion',
        'pn-übergang',
        'pn junction',
        'raumladungszone',
        'depletion',
        'mosfet',
        'transistor',
        'bipolar',
        'kristall',
        'crystal',
        'eigenleitung',
        'intrinsic',
        'rekombination',
        'recombination',
      ],
    ),
    SubjectProfile(
      id: 'em_field_theory',
      name: 'Electromagnetic field theory',
      localName: 'Elektromagnetische Feldtheorie',
      guidance:
          'Subject: electromagnetic field theory: vector analysis (gradient, divergence, curl/rot, Nabla operator, '
          'coordinate systems), Maxwell equations in integral and differential form, electrostatics (Coulomb, Gauss '
          'law, potential, Poisson and Laplace equation, capacitance, image charges, energy), stationary currents, '
          'magnetostatics (Biot–Savart, Ampère, vector potential, inductance), boundary conditions at interfaces, '
          'quasi-stationary fields (induction, skin effect), electromagnetic waves (wave equation, plane waves, '
          'polarisation, Poynting vector, reflection and transmission), transmission lines. Prefer formula cards '
          'with symbol legends and units (E, D, H, B, ε0, μ0), recipes (e.g. choosing a Gaussian surface, solving '
          'with symmetry, applying boundary conditions), theorems (Gauss, Stokes, uniqueness) and SVG sketches of '
          'field lines and geometries.',
      extraMix: {'formula': 3, 'math_recipe': 2, 'theorem': 1.5, 'calc_exercise': 2, 'visual': 1.5},
      keywords: [
        'maxwell',
        'elektrisches feld',
        'electric field',
        'magnetfeld',
        'magnetic field',
        'feldstärke',
        'potential',
        'gaußscher satz',
        'gauss',
        'stokes',
        'divergenz',
        'divergence',
        'rotation',
        'curl',
        'nabla',
        'poisson',
        'laplace-gleichung',
        'biot',
        'ampère',
        'ampere',
        'induktion',
        'induction',
        'welle',
        'wave',
        'poynting',
        'permittivität',
        'permeabilität',
        'ladung',
        'charge',
        'kapazität',
        'capacitance',
      ],
    ),
    SubjectProfile(
      id: 'math',
      name: 'Mathematics (general)',
      localName: 'Mathematik',
      guidance:
          'Subject: mathematics. State definitions and theorems precisely with assumptions, explain procedures as '
          'step-by-step recipes and practise them with calculations.',
      extraMix: {'theorem': 2, 'math_recipe': 2, 'calc_exercise': 1.5, 'formula': 1, 'visual': 1},
      keywords: [
        'satz',
        'theorem',
        'lemma',
        'beweis',
        'proof',
        'definition',
        'korollar',
        'corollary',
        'matrix',
        'vektor',
      ],
    ),
    SubjectProfile(
      id: 'physics',
      name: 'Physics / Engineering',
      localName: 'Physik / Technik',
      guidance:
          'Subject: physics/engineering. Use formula cards with symbol legends and SI units, numeric calculation '
          'exercises with realistic values, and sketches of setups.',
      extraMix: {'formula': 2, 'calc_exercise': 2, 'visual': 1.5, 'math_recipe': 1},
      keywords: [
        'energie',
        'energy',
        'kraft',
        'force',
        'spannung',
        'voltage',
        'strom',
        'current',
        'leistung',
        'power',
        'masse',
        'joule',
        'watt',
      ],
    ),
  ];

  static SubjectProfile byId(String id) => all.firstWhere((p) => p.id == id, orElse: () => general);

  /// Picks the best matching profile for a text, or `general`.
  static String detect(String text) {
    final lower = text.toLowerCase();
    var bestId = 'general';
    var bestScore = 0.0;
    for (final p in all) {
      if (p.keywords.isEmpty) continue;
      var score = 0.0;
      for (final k in p.keywords) {
        score += RegExp(RegExp.escape(k)).allMatches(lower).length.clamp(0, 15);
      }
      // Specific course profiles win over the generic ones on ties.
      if (p.id == 'math' || p.id == 'physics') score *= 0.6;
      if (score > bestScore) {
        bestScore = score;
        bestId = p.id;
      }
    }
    // Require some evidence relative to the text length.
    final words = lower.split(RegExp(r'\s+')).length;
    return bestScore >= 4 && bestScore >= words / 400 ? bestId : 'general';
  }
}
