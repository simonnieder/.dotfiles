#import "@preview/curryst:0.5.1": prooftree, rule
#let proof(body) = [
  _Proof._
  #body #h(1fr) $square$
]

#let ans = strong[Answer:]

#let qblock(question, answer) = [
  + #question

    #ans

    #answer
    #v(1fr)
]

#let important(color: aqua, bold: true, title, body) = {
  let has-title = title != [] and title != ""
  let has-body = body != [] and body != ""

  let title_real = if bold [*#title*] else [#title]

  if not has-title and not has-body {
    []
  } else {
    box(
      stack(
        spacing: 0pt,
        if has-title {
          box(
            radius: (
              top-left: 5pt,
              top-right: 5pt,
              bottom-right: if has-body { 0pt } else { 5pt },
              bottom-left: if has-body { 0pt } else { 5pt },
            ),
            stroke: color,
            fill: color,
            inset: .5em,
          )[#title_real]
        },
        if has-body {
          box(
            radius: (
              top-left: if has-title { 0pt } else { 5pt },
              top-right: 5pt,
              bottom-right: 5pt,
              bottom-left: 5pt,
            ),
            stroke: color,
            inset: .5em,
            width: 100%,
          )[#body]
        },
      ),
    )
  }
}

#let conf(title, assignment_title, doc) = {
  set page(
    paper: "a4",
    header-ascent: 14pt,
    header: {
      set text(size: 8pt)
      grid(
        columns: (1fr, 1fr, 1fr),
        rows: (auto, auto),
        align: (left, center, right),
        gutter: 6pt,
        "Simon Niederwolfsgruber", title, datetime.today().display(),
        "12122091", "", assignment_title,
      )
    },
    footer-descent: 12pt,
    footer: context {
      set align(center)
      set text(size: 8pt)
      counter(page).display("1")
    },
  )
  doc
}


//logic
#let namerule(desc) = rule.with(name: $(italic(#desc))$)


//#show text: set text(navy)
