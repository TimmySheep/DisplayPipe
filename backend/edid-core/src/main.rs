mod edid;
fn main() {
 let a:Vec<String>=std::env::args().collect();
 let run=||->Result<serde_json::Value,Box<dyn std::error::Error>> {
  let b=std::fs::read(a.get(2).ok_or("missing EDID file")?)?;
  edid::validate(&b)?;
  if a.get(1).map(String::as_str)==Some("parse") {return Ok(serde_json::to_value(edid::parse(&b)?)?)}
  if a.get(1).map(String::as_str)!=Some("cap") {return Err("parse or cap required".into())}
  let hz:f64=a.get(3).ok_or("missing cap")?.parse()?;
  let r=edid::cap(&b,&edid::CapOptions{max_hz:hz,max_pixel_clock_mhz:None})?;
  Ok(serde_json::to_value(r)?)
 };
 match run(){Ok(v)=>println!("{}",v),Err(e)=>{eprintln!("{}",e);std::process::exit(2)}}
}
